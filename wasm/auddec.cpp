#include "moonlight_wasm.hpp"

#include <emscripten.h>
#include <stdlib.h>

extern "C" int g_AudioJitterMsOverride;

static size_t s_samplesPerFrame = 0;
static size_t s_channelCount = 0;
static int s_sampleRate = 0;

static OpusMSDecoder* s_OpusDecoder = nullptr;

int MoonlightInstance::AudDecInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int arFlags) {
  s_channelCount = (size_t)opusConfig->channelCount;
  s_samplesPerFrame = (size_t)opusConfig->samplesPerFrame;
  s_sampleRate = opusConfig->sampleRate;

  int rc;
  s_OpusDecoder = opus_multistream_decoder_create(
    opusConfig->sampleRate, opusConfig->channelCount,
    opusConfig->streams, opusConfig->coupledStreams,
    opusConfig->mapping, &rc);
  g_Instance->m_OpusDecoder = s_OpusDecoder;
  if (!s_OpusDecoder) {
    return -1;
  }

  const int targetJitterMs = (g_AudioJitterMsOverride != 0) ? g_AudioJitterMsOverride : 100;
  MAIN_THREAD_ASYNC_EM_ASM({
    window._mlAudioTargetMs = $0;
  }, targetJitterMs);

  return 0;
}

void MoonlightInstance::AudDecCleanup(void) {
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
    return;
  }

  size_t frameElems = s_samplesPerFrame * s_channelCount;
  opus_int16* dst = (opus_int16*)malloc(frameElems * sizeof(*dst));
  if (!dst) {
    return;
  }

  int decodedSamples = opus_multistream_decode(
    s_OpusDecoder, (const unsigned char*)sampleData, sampleLength,
    dst, (int)s_samplesPerFrame, 0);
  if (decodedSamples <= 0) {
    free(dst);
    return;
  }

  int framePtr = (int)(size_t)dst;
  int samplesPerFrame = decodedSamples;
  int channels = (int)s_channelCount;
  int sampleRate = s_sampleRate;
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
