#include "moonlight_wasm.hpp"

#include <emscripten.h>
#include <stdlib.h>

extern "C" int g_AudioJitterMsOverride;

static size_t s_samplesPerFrame = 0;
static size_t s_channelCount = 0;
static int s_sampleRate = 0;

static OpusMSDecoder* s_OpusDecoder = nullptr;
static uint64_t s_audioInitTimeMs = 0;
static uint32_t s_decodeCalls = 0;
static uint32_t s_decodeFailures = 0;
static uint32_t s_framesPosted = 0;
static uint32_t s_plcRequests = 0;
static bool s_loggedFirstDecodedFrame = false;

int MoonlightInstance::AudDecInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int arFlags) {
  s_channelCount = (size_t)opusConfig->channelCount;
  s_samplesPerFrame = (size_t)opusConfig->samplesPerFrame;
  s_sampleRate = opusConfig->sampleRate;
  s_audioInitTimeMs = LiGetMillis();
  s_decodeCalls = 0;
  s_decodeFailures = 0;
  s_framesPosted = 0;
  s_plcRequests = 0;
  s_loggedFirstDecodedFrame = false;

  const int targetJitterMs = (g_AudioJitterMsOverride != 0) ? g_AudioJitterMsOverride : 100;
  ClLogMessage("Audio decoder init: audioConfig=0x%x, sampleRate=%d, channels=%zu, streams=%d, coupledStreams=%d, samplesPerFrame=%zu, arFlags=0x%x, targetJitterMs=%d\n",
    audioConfiguration, s_sampleRate, s_channelCount, opusConfig->streams,
    opusConfig->coupledStreams, s_samplesPerFrame, arFlags, targetJitterMs);

  int rc;
  s_OpusDecoder = opus_multistream_decoder_create(
    opusConfig->sampleRate, opusConfig->channelCount,
    opusConfig->streams, opusConfig->coupledStreams,
    opusConfig->mapping, &rc);
  g_Instance->m_OpusDecoder = s_OpusDecoder;
  if (!s_OpusDecoder) {
    ClLogMessage("Audio decoder creation failed: opusError=%d, sampleRate=%d, channels=%zu, streams=%d, coupledStreams=%d\n",
      rc, s_sampleRate, s_channelCount, opusConfig->streams, opusConfig->coupledStreams);
    return -1;
  }

  MAIN_THREAD_ASYNC_EM_ASM({
    window._mlAudioTargetMs = $0;
  }, targetJitterMs);

  ClLogMessage("Audio decoder initialized successfully\n");

  return 0;
}

void MoonlightInstance::AudDecCleanup(void) {
  ClLogMessage("Audio decoder cleanup: lifetimeMs=%llu, decodeCalls=%u, framesPosted=%u, decodeFailures=%u, plcRequests=%u\n",
    (unsigned long long)(s_audioInitTimeMs ? LiGetMillis() - s_audioInitTimeMs : 0),
    s_decodeCalls, s_framesPosted, s_decodeFailures, s_plcRequests);

  MAIN_THREAD_ASYNC_EM_ASM({
    if (typeof stopAudioScheduler === 'function') {
      stopAudioScheduler();
    }
  });

  if (s_OpusDecoder) {
    opus_multistream_decoder_destroy(s_OpusDecoder);
    s_OpusDecoder = nullptr;
    g_Instance->m_OpusDecoder = nullptr;
  }
}

void MoonlightInstance::AudDecDecodeAndPlaySample(char* sampleData, int sampleLength) {
  if (!s_OpusDecoder) {
    ClLogMessage("Audio decode skipped because decoder is not initialized: sampleLength=%d\n", sampleLength);
    return;
  }

  s_decodeCalls++;
  if (sampleData == NULL || sampleLength == 0) {
    s_plcRequests++;
    if (s_plcRequests <= 3 || (s_plcRequests % 100) == 0) {
      ClLogMessage("Audio decoder received packet-loss concealment request: count=%u\n", s_plcRequests);
    }
  }

  size_t frameElems = s_samplesPerFrame * s_channelCount;
  opus_int16* dst = (opus_int16*)malloc(frameElems * sizeof(*dst));
  if (!dst) {
    ClLogMessage("Audio decode malloc failed: frameElems=%zu, bytes=%zu\n",
      frameElems, frameElems * sizeof(*dst));
    return;
  }

  int decodedSamples = opus_multistream_decode(
    s_OpusDecoder, (const unsigned char*)sampleData, sampleLength,
    dst, (int)s_samplesPerFrame, 0);
  if (decodedSamples <= 0) {
    s_decodeFailures++;
    if (s_decodeFailures <= 10 || (s_decodeFailures % 100) == 0) {
      ClLogMessage("Audio decode failed: opusResult=%d, sampleLength=%d, decodeCalls=%u, failures=%u\n",
        decodedSamples, sampleLength, s_decodeCalls, s_decodeFailures);
    }
    free(dst);
    return;
  }

  if (!s_loggedFirstDecodedFrame) {
    s_loggedFirstDecodedFrame = true;
    ClLogMessage("First decoded audio frame after %llu ms: encodedBytes=%d, decodedSamples=%d, channels=%zu, sampleRate=%d\n",
      (unsigned long long)(s_audioInitTimeMs ? LiGetMillis() - s_audioInitTimeMs : 0),
      sampleLength, decodedSamples, s_channelCount, s_sampleRate);
  }

  int framePtr = (int)(size_t)dst;
  int samplesPerFrame = decodedSamples;
  int channels = (int)s_channelCount;
  int sampleRate = s_sampleRate;
  s_framesPosted++;
  MAIN_THREAD_ASYNC_EM_ASM({
    try {
      if (typeof _audReceiveFrame === 'function') {
        _audReceiveFrame($0, $1, $2, $3);
      }
    } finally {
      _free($0);
    }
  }, framePtr, samplesPerFrame, channels, sampleRate);
}

AUDIO_RENDERER_CALLBACKS MoonlightInstance::s_ArCallbacks = {
  .init = MoonlightInstance::AudDecInit,
  .cleanup = MoonlightInstance::AudDecCleanup,
  .decodeAndPlaySample = MoonlightInstance::AudDecDecodeAndPlaySample,
  .capabilities = CAPABILITY_DIRECT_SUBMIT | CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
};
