#include "moonlight_wasm.hpp"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>

#include <emscripten.h>

#include "samsung/wasm/elementary_media_packet.h"
#include "samsung/wasm/operation_result.h"

extern "C" int g_AudioJitterMsOverride;

namespace {

using TimeStamp = samsung::wasm::Seconds;
using OperationResult = samsung::wasm::OperationResult;

constexpr int kMaxChannels = 8;
constexpr int kPcmRingCapacityFrames = 48000;

enum SharedControlIndex {
  kWriteFrame = 0,
  kReadFrame = 1,
  kGeneration = 2,
  kTargetFrames = 3,
  kMaximumTargetFrames = 4,
  kMinimumTargetFrames = 5,
  kPacketFrames = 6,
  kUnderruns = 7,
  kOverruns = 8,
  kSkippedFrames = 9,
  kDecodedFrames = 10,
  kActive = 11,
  kSharedControlCount = 12,
};

alignas(4) static int32_t s_sharedControl[kSharedControlCount] = {};
alignas(4) static opus_int16 s_pcmRing[kPcmRingCapacityFrames * kMaxChannels] = {};

static size_t s_samplesPerFrame = 0;
static size_t s_channelCount = 0;
static int s_sampleRate = 0;
static OpusMSDecoder* s_opusDecoder = nullptr;
static std::vector<opus_int16> s_decodeBuffer;
static std::atomic<bool> s_audioRunning(false);
static bool s_workletAttached = false;
static uint64_t s_audioInitTimeMs = 0;
static uint64_t s_audioSampleCursor = 0;
static uint32_t s_decodeCalls = 0;
static uint32_t s_decodeFailures = 0;
static uint32_t s_framesPosted = 0;
static uint32_t s_nativeAppends = 0;
static uint32_t s_nativeDrops = 0;
static uint32_t s_nativeAppendErrors = 0;
static uint64_t s_nativeTotalAppendDurationMs = 0;
static uint32_t s_nativeMaxAppendDurationMs = 0;
static uint32_t s_plcRequests = 0;
static bool s_loggedFirstDecodedFrame = false;

inline int32_t AtomicLoad(int index) {
  return __atomic_load_n(&s_sharedControl[index], __ATOMIC_ACQUIRE);
}

inline void AtomicStore(int index, int32_t value) {
  __atomic_store_n(&s_sharedControl[index], value, __ATOMIC_RELEASE);
}

inline int32_t AtomicAdd(int index, int32_t value) {
  return __atomic_add_fetch(&s_sharedControl[index], value, __ATOMIC_ACQ_REL);
}

void ResetSharedRing(int targetJitterMs) {
  const int packetFrames = static_cast<int>(s_samplesPerFrame);
  const int maximumFrames = std::max(packetFrames, (s_sampleRate * targetJitterMs) / 1000);
  const int minimumFrames = std::min(
    maximumFrames,
    std::max(packetFrames * 2, s_sampleRate / 100));

  AtomicStore(kWriteFrame, 0);
  AtomicStore(kReadFrame, 0);
  AtomicAdd(kGeneration, 1);
  AtomicStore(kTargetFrames, minimumFrames);
  AtomicStore(kMaximumTargetFrames, maximumFrames);
  AtomicStore(kMinimumTargetFrames, minimumFrames);
  AtomicStore(kPacketFrames, packetFrames);
  AtomicStore(kUnderruns, 0);
  AtomicStore(kOverruns, 0);
  AtomicStore(kSkippedFrames, 0);
  AtomicStore(kDecodedFrames, 0);
  AtomicStore(kActive, 0);
}

bool AttachWebAudioRing() {
  const int controlPtr = static_cast<int>(reinterpret_cast<intptr_t>(s_sharedControl));
  const int pcmPtr = static_cast<int>(reinterpret_cast<intptr_t>(s_pcmRing));
  return MAIN_THREAD_EM_ASM_INT({
    try {
      if (!window.MoonlightAudio || typeof window.MoonlightAudio.attachSharedRing !== 'function') {
        return 0;
      }
      return window.MoonlightAudio.attachSharedRing(
        $0, $1, $2, $3, $4
      ) ? 1 : 0;
    } catch (error) {
      if (typeof window.moonlightDebugLog === 'function') {
        window.moonlightDebugLog('error', 'audio shared ring attach failed', {
          source: 'auddec.cpp',
          error: error && error.message ? error.message : String(error)
        });
      }
      return 0;
    }
  }, controlPtr, pcmPtr, kPcmRingCapacityFrames, static_cast<int>(s_channelCount), s_sampleRate) != 0;
}

void WriteWebAudioRing(const opus_int16* samples, int decodedSamples) {
  int32_t writeFrame = AtomicLoad(kWriteFrame);
  int32_t readFrame = AtomicLoad(kReadFrame);
  int32_t availableFrames = writeFrame - readFrame;
  if (availableFrames < 0) {
    readFrame = writeFrame;
    availableFrames = 0;
    AtomicStore(kReadFrame, readFrame);
  }

  if (availableFrames + decodedSamples > kPcmRingCapacityFrames) {
    const int32_t framesToDiscard = availableFrames + decodedSamples - kPcmRingCapacityFrames;
    readFrame += framesToDiscard;
    AtomicStore(kReadFrame, readFrame);
    AtomicAdd(kOverruns, 1);
    AtomicAdd(kSkippedFrames, framesToDiscard);
  }

  for (int frame = 0; frame < decodedSamples; frame++) {
    const int ringFrame = (writeFrame + frame) % kPcmRingCapacityFrames;
    opus_int16* destination = &s_pcmRing[ringFrame * s_channelCount];
    const opus_int16* source = &samples[frame * s_channelCount];
    std::memcpy(destination, source, s_channelCount * sizeof(opus_int16));
  }

  AtomicStore(kWriteFrame, writeFrame + decodedSamples);
  AtomicAdd(kDecodedFrames, decodedSamples);
}

void PostWebAudioFallback(const opus_int16* samples, int decodedSamples) {
  const size_t frameElements = static_cast<size_t>(decodedSamples) * s_channelCount;
  opus_int16* copy = static_cast<opus_int16*>(std::malloc(frameElements * sizeof(opus_int16)));
  if (!copy) {
    MoonlightInstance::ClLogMessage("WebAudio fallback allocation failed: elements=%zu\n", frameElements);
    return;
  }
  std::memcpy(copy, samples, frameElements * sizeof(opus_int16));

  const int framePtr = static_cast<int>(reinterpret_cast<intptr_t>(copy));
  const uint32_t postedAtMs = LiGetMillis();
  MAIN_THREAD_ASYNC_EM_ASM({
    try {
      if (typeof _audReceiveFrame === 'function') {
        _audReceiveFrame($0, $1, $2, $3, $4);
      }
    } finally {
      _free($0);
    }
  }, framePtr, decodedSamples, static_cast<int>(s_channelCount), s_sampleRate, postedAtMs);
}

}  // namespace

void MoonlightInstance::SubmitNativeAudioFrame(
    const opus_int16* samples, int decodedSamples,
    const AUDIO_FRAME_METADATA* metadata) {
  if (!s_audioRunning.load() || !g_Instance->m_AudioStarted.load()) {
    s_nativeDrops++;
    return;
  }

  const int pendingDurationMs = LiGetPendingAudioDuration();
  double audioPts = 0.0;
  AUDIO_FRAME_METADATA fallbackMetadata = {};
  if (metadata == nullptr) {
    fallbackMetadata.isConcealment = false;
    fallbackMetadata.timestampValid = false;
    metadata = &fallbackMetadata;
  }
  if (!g_Instance->PrepareNativeAudioFrame(*metadata, pendingDurationMs, &audioPts)) {
    s_nativeDrops++;
    if (s_nativeDrops <= 5 || (s_nativeDrops % 100) == 0) {
      MoonlightInstance::ClLogMessage(
        "Native audio policy drop: rawPtsMs=%u, timestampValid=%d, plc=%d, pendingMs=%d, drops=%u\n",
        metadata->presentationTimeMs, metadata->timestampValid,
        metadata->isConcealment, pendingDurationMs, s_nativeDrops);
    }
    return;
  }

  samsung::wasm::ElementaryMediaPacket packet {
    TimeStamp(audioPts),
    TimeStamp(audioPts),
    TimeStamp(static_cast<double>(decodedSamples) / s_sampleRate),
    true,
    static_cast<size_t>(decodedSamples) * s_channelCount * sizeof(opus_int16),
    samples,
    0,
    0,
    0,
    0,
    g_Instance->m_AudioSessionId.load(),
  };

  const uint64_t appendStartMs = LiGetMillis();
  auto result = g_Instance->m_AudioTrack.AppendPacketAsync(packet);
  const uint64_t appendDurationMs = LiGetMillis() - appendStartMs;
  s_nativeTotalAppendDurationMs += appendDurationMs;
  s_nativeMaxAppendDurationMs = std::max(
    s_nativeMaxAppendDurationMs, static_cast<uint32_t>(appendDurationMs));
  if (result) {
    if (s_nativeAppends == 0 || (s_nativeAppends % 100) == 0) {
      g_Instance->LogEmssAudioClock(
        "stream-native-audio-append",
        audioPts);
    }
    if (appendDurationMs > 2) {
      MoonlightInstance::ClLogMessage(
        "Native audio append duration: durationMs=%llu, audioPts=%.6f, pendingMs=%d\n",
        static_cast<unsigned long long>(appendDurationMs), audioPts,
        pendingDurationMs);
    }
    s_nativeAppends++;
    return;
  }

  s_nativeAppendErrors++;
  if (result.operation_result == OperationResult::kAppendIgnored) {
    s_nativeDrops++;
    return;
  }

  if (s_nativeAppendErrors <= 10 || (s_nativeAppendErrors % 100) == 0) {
    MoonlightInstance::ClLogMessage(
      "Native audio append failed: result=%d, errors=%u, sessionId=%u, pendingMs=%d\n",
      static_cast<int>(result.operation_result), s_nativeAppendErrors,
      static_cast<unsigned int>(g_Instance->m_AudioSessionId.load()), pendingDurationMs);
  }
}

int MoonlightInstance::AudDecInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int arFlags) {
  const int configuredChannelCount = g_Instance->m_AudioChannelCount.load();
  const int configuredSampleRate = g_Instance->m_AudioSampleRate.load();
  s_channelCount = static_cast<size_t>(opusConfig->channelCount);
  s_samplesPerFrame = static_cast<size_t>(opusConfig->samplesPerFrame);
  s_sampleRate = opusConfig->sampleRate;
  s_audioInitTimeMs = LiGetMillis();
  s_audioSampleCursor = 0;
  s_decodeCalls = 0;
  s_decodeFailures = 0;
  s_framesPosted = 0;
  s_nativeAppends = 0;
  s_nativeDrops = 0;
  s_nativeAppendErrors = 0;
  s_nativeTotalAppendDurationMs = 0;
  s_nativeMaxAppendDurationMs = 0;
  s_plcRequests = 0;
  s_loggedFirstDecodedFrame = false;
  s_workletAttached = false;
  s_audioRunning.store(false);

  if (s_channelCount == 0 || s_channelCount > kMaxChannels || s_sampleRate <= 0 || s_samplesPerFrame == 0) {
    ClLogMessage("Audio decoder configuration invalid: sampleRate=%d, channels=%zu, samplesPerFrame=%zu\n",
      s_sampleRate, s_channelCount, s_samplesPerFrame);
    return -1;
  }
  if (g_Instance->m_AudioBackend == AudioBackend::NativeEmss &&
      (configuredChannelCount != static_cast<int>(s_channelCount) || configuredSampleRate != s_sampleRate)) {
    ClLogMessage("Native audio negotiation differs from configured EMSS track: track=%d Hz/%d channels, opus=%d Hz/%zu channels\n",
      configuredSampleRate, configuredChannelCount, s_sampleRate, s_channelCount);
    return -1;
  }

  const int targetJitterMs = g_Instance->m_AudioBackend == AudioBackend::NativeEmss
    ? 0
    : (g_AudioJitterMsOverride != 0 ? g_AudioJitterMsOverride : 100);
  ClLogMessage("Audio decoder init: backend=%s, audioConfig=0x%x, sampleRate=%d, channels=%zu, streams=%d, coupledStreams=%d, samplesPerFrame=%zu, arFlags=0x%x, maximumBufferMs=%d\n",
    g_Instance->m_AudioBackend == AudioBackend::NativeEmss ? "emss" : "webaudio",
    audioConfiguration, s_sampleRate, s_channelCount, opusConfig->streams,
    opusConfig->coupledStreams, s_samplesPerFrame, arFlags, targetJitterMs);

  int opusResult = OPUS_OK;
  s_opusDecoder = opus_multistream_decoder_create(
    opusConfig->sampleRate, opusConfig->channelCount,
    opusConfig->streams, opusConfig->coupledStreams,
    opusConfig->mapping, &opusResult);
  g_Instance->m_OpusDecoder = s_opusDecoder;
  if (!s_opusDecoder) {
    ClLogMessage("Audio decoder creation failed: opusError=%d\n", opusResult);
    return -1;
  }

  s_decodeBuffer.resize(s_samplesPerFrame * s_channelCount);
  g_Instance->m_AudioSampleRate.store(s_sampleRate);
  g_Instance->m_AudioChannelCount.store(static_cast<int>(s_channelCount));
  g_Instance->m_AudioSamplesPerFrame.store(static_cast<int>(s_samplesPerFrame));

  ResetSharedRing(targetJitterMs);
  if (g_Instance->m_AudioBackend == AudioBackend::WebAudio) {
    s_workletAttached = AttachWebAudioRing();
    ClLogMessage("WebAudio sink selected: mode=%s\n",
      s_workletAttached ? "audio-worklet-shared-ring" : "buffer-source-fallback");
  }

  return 0;
}

void MoonlightInstance::AudDecStart(void) {
  s_audioRunning.store(true);
  AtomicStore(kActive, 1);
  ClLogMessage("Audio renderer started: backend=%s\n",
    g_Instance->m_AudioBackend == AudioBackend::NativeEmss ? "emss" : "webaudio");
}

void MoonlightInstance::AudDecStop(void) {
  s_audioRunning.store(false);
  AtomicStore(kActive, 0);
  AtomicStore(kReadFrame, AtomicLoad(kWriteFrame));
  AtomicAdd(kGeneration, 1);
  ClLogMessage("Audio renderer stopped\n");
}

void MoonlightInstance::AudDecCleanup(void) {
  AudDecStop();
  uint32_t timestampRebases = 0;
  uint32_t resyncCount = 0;
  double lastAudioPtsMs = 0.0;
  double lastVideoPtsMs = 0.0;
  {
    std::lock_guard<std::mutex> lock(g_Instance->m_AudioPolicyMutex);
    timestampRebases = g_Instance->m_EmssAudioPolicy.TimestampRebases();
    resyncCount = g_Instance->m_EmssAudioPolicy.ResyncCount();
    lastAudioPtsMs = g_Instance->m_EmssAudioPolicy.LastAudioPtsMs();
    lastVideoPtsMs = g_Instance->m_EmssAudioPolicy.LastVideoPtsMs();
  }
  ClLogMessage("Audio decoder cleanup: lifetimeMs=%llu, decodeCalls=%u, framesPosted=%u, nativeAppends=%u, nativeDrops=%u, nativeAppendErrors=%u, nativeAppendAverageMs=%.3f, nativeAppendMaxMs=%u, decodeFailures=%u, plcRequests=%u, lastAudioPtsMs=%.3f, lastVideoPtsMs=%.3f, clockDeltaMs=%.3f, timestampRebases=%u, resyncCount=%u, workletUnderruns=%d, workletOverruns=%d, workletSkippedFrames=%d\n",
    static_cast<unsigned long long>(s_audioInitTimeMs ? LiGetMillis() - s_audioInitTimeMs : 0),
    s_decodeCalls, s_framesPosted, s_nativeAppends, s_nativeDrops, s_nativeAppendErrors,
    s_nativeAppends ? static_cast<double>(s_nativeTotalAppendDurationMs) / s_nativeAppends : 0.0,
    s_nativeMaxAppendDurationMs, s_decodeFailures, s_plcRequests,
    lastAudioPtsMs, lastVideoPtsMs, lastAudioPtsMs - lastVideoPtsMs,
    timestampRebases, resyncCount,
    AtomicLoad(kUnderruns), AtomicLoad(kOverruns),
    AtomicLoad(kSkippedFrames));

  if (g_Instance->m_AudioBackend == AudioBackend::WebAudio) {
    MAIN_THREAD_ASYNC_EM_ASM({
      if (window.MoonlightAudio && typeof window.MoonlightAudio.detachSharedRing === 'function') {
        window.MoonlightAudio.detachSharedRing();
      }
    });
  }

  if (s_opusDecoder) {
    opus_multistream_decoder_destroy(s_opusDecoder);
    s_opusDecoder = nullptr;
    g_Instance->m_OpusDecoder = nullptr;
  }
  s_decodeBuffer.clear();
  g_Instance->m_AudioSampleRate.store(0);
  g_Instance->m_AudioChannelCount.store(0);
  g_Instance->m_AudioSamplesPerFrame.store(0);
}

void MoonlightInstance::AudDecDecodeAndPlaySample(char* sampleData, int sampleLength) {
  AUDIO_FRAME_METADATA metadata = {};
  metadata.timestampValid = false;
  metadata.isConcealment = sampleData == nullptr || sampleLength == 0;
  AudDecDecodeAndPlaySampleEx(sampleData, sampleLength, &metadata);
}

void MoonlightInstance::AudDecDecodeAndPlaySampleEx(
    char* sampleData, int sampleLength,
    const AUDIO_FRAME_METADATA* metadata) {
  if (!s_opusDecoder) {
    return;
  }

  s_decodeCalls++;
  if (sampleData == nullptr || sampleLength == 0) {
    s_plcRequests++;
  }

  const int decodedSamples = opus_multistream_decode(
    s_opusDecoder, reinterpret_cast<const unsigned char*>(sampleData), sampleLength,
    s_decodeBuffer.data(), static_cast<int>(s_samplesPerFrame), 0);
  if (decodedSamples <= 0) {
    s_decodeFailures++;
    if (s_decodeFailures <= 10 || (s_decodeFailures % 100) == 0) {
      ClLogMessage("Audio decode failed: opusResult=%d, sampleLength=%d, failures=%u\n",
        decodedSamples, sampleLength, s_decodeFailures);
    }
    return;
  }

  s_audioSampleCursor += static_cast<uint64_t>(decodedSamples);

  if (!s_loggedFirstDecodedFrame) {
    s_loggedFirstDecodedFrame = true;
    ClLogMessage("First decoded audio frame after %llu ms: encodedBytes=%d, decodedSamples=%d, channels=%zu, sampleRate=%d\n",
      static_cast<unsigned long long>(s_audioInitTimeMs ? LiGetMillis() - s_audioInitTimeMs : 0),
      sampleLength, decodedSamples, s_channelCount, s_sampleRate);
  }

  if (g_Instance->m_AudioBackend == AudioBackend::NativeEmss) {
    SubmitNativeAudioFrame(s_decodeBuffer.data(), decodedSamples, metadata);
  } else if (s_workletAttached) {
    WriteWebAudioRing(s_decodeBuffer.data(), decodedSamples);
    s_framesPosted++;
  } else {
    PostWebAudioFallback(s_decodeBuffer.data(), decodedSamples);
    s_framesPosted++;
  }
}

AUDIO_RENDERER_CALLBACKS MoonlightInstance::s_WebAudioCallbacks = {
  .init = MoonlightInstance::AudDecInit,
  .start = MoonlightInstance::AudDecStart,
  .stop = MoonlightInstance::AudDecStop,
  .cleanup = MoonlightInstance::AudDecCleanup,
  .decodeAndPlaySample = MoonlightInstance::AudDecDecodeAndPlaySample,
  .capabilities = CAPABILITY_DIRECT_SUBMIT | CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
  .decodeAndPlaySampleEx = nullptr,
};

AUDIO_RENDERER_CALLBACKS MoonlightInstance::s_NativeAudioCallbacks = {
  .init = MoonlightInstance::AudDecInit,
  .start = MoonlightInstance::AudDecStart,
  .stop = MoonlightInstance::AudDecStop,
  .cleanup = MoonlightInstance::AudDecCleanup,
  .decodeAndPlaySample = MoonlightInstance::AudDecDecodeAndPlaySample,
  .capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
  .decodeAndPlaySampleEx = MoonlightInstance::AudDecDecodeAndPlaySampleEx,
};
