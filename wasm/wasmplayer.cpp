#include "moonlight_wasm.hpp"

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <sstream>
#include <vector>

#include <h264_stream.h>

#include <assert.h>
#include <pthread.h>

#include "samsung/wasm/elementary_audio_track_config.h"
#include "samsung/wasm/elementary_media_packet.h"
#include "samsung/wasm/elementary_video_track_config.h"
#include "samsung/html/html_media_element_listener.h"
#include "samsung/wasm/operation_result.h"

#define INITIAL_DECODE_BUFFER_LEN 1024 * 1024
#define MAX_SPS_EXTRA_SIZE 32

using std::chrono_literals::operator""s;
using std::chrono_literals::operator""ms;
using EmssReadyState = samsung::wasm::ElementaryMediaStreamSource::ReadyState;
using EmssOperationResult = samsung::wasm::OperationResult;
using EmssLatencyMode = samsung::wasm::ElementaryMediaStreamSource::LatencyMode;
using EmssRenderingMode = samsung::wasm::ElementaryMediaStreamSource::RenderingMode;
using EmssAsyncResult = samsung::wasm::OperationResult;
using HTMLAsyncResult = samsung::wasm::OperationResult;
using TimeStamp = samsung::wasm::Seconds;

static constexpr TimeStamp kFrameTimeMargin = 0.5ms;
static constexpr TimeStamp kTimeWindow = 1s;
static uint32_t s_VideoFormat = 0;
static uint32_t s_Width = 0;
static uint32_t s_Height = 0;
static uint32_t s_Framerate = 0;

static std::vector<unsigned char> s_DecodeBuffer;

static TimeStamp s_frameDuration;
static TimeStamp s_pktPts;

static TimeStamp s_ptsDiff;
static TimeStamp s_lastSec;

static std::chrono::time_point<std::chrono::steady_clock> s_firstAppend;
static std::chrono::time_point<std::chrono::steady_clock> s_lastTime;

static bool s_hasFirstFrame = false;
static bool s_FramePacingEnabled = false;
static bool s_loggedFirstDecodeUnit = false;
static bool s_loggedFirstAppend = false;
static uint32_t s_DecodeUnitsBeforeVideoStart = 0;
static uint64_t s_VideoSetupStartMs = 0;
static constexpr uint32_t kEmssSourceStateTimeoutMs = 5000;
static constexpr uint32_t kEmssAudioTrackTimeoutMs = 10000;
static constexpr uint32_t kEmssVideoTrackTimeoutMs = 10000;
static constexpr uint32_t kEmssPlayTimeoutMs = 5000;

static uint32_t total_bytes = 0;
static int m_LastFrameNumber = 0;

static std::string s_StatString = "";

static VIDEO_STATS m_ActiveWndVideoStats;
static VIDEO_STATS m_LastWndVideoStats;
static VIDEO_STATS m_GlobalVideoStats;

namespace {

struct H264ProfileSelection {
  const char* mimeType;
  const char* label;
};

struct VideoProfileSelection {
  const char* mimeType;
  const char* label;
};

struct VideoFormatCandidate {
  const char* codec;
  bool hdr;
  int videoFormat;
  int serverCodecMode;
};

const char* BoolText(bool value) {
  return value ? "true" : "false";
}

struct AsyncOperationWait {
  std::mutex mutex;
  std::condition_variable condition;
  bool done = false;
  bool success = false;
  int result = 0;
};

uint64_t CalculateH264MacroblocksPerSecond(int width, int height, int framerate) {
  if (width <= 0 || height <= 0 || framerate <= 0) {
    return 0;
  }

  const uint64_t macroblockWidth = (static_cast<uint64_t>(width) + 15) / 16;
  const uint64_t macroblockHeight = (static_cast<uint64_t>(height) + 15) / 16;
  return macroblockWidth * macroblockHeight * static_cast<uint64_t>(framerate);
}

H264ProfileSelection SelectH264Profile(int width, int height, int framerate) {
  const uint64_t macroblocksPerSecond = CalculateH264MacroblocksPerSecond(width, height, framerate);

  if (macroblocksPerSecond <= 522240) {
    return { "video/mp4; codecs=\"avc1.64002A\"", "H.264 High Level Profile 4.2" };
  }
  if (macroblocksPerSecond <= 983040) {
    return { "video/mp4; codecs=\"avc1.640033\"", "H.264 High Level Profile 5.1" };
  }
  return { "video/mp4; codecs=\"avc1.640034\"", "H.264 High Level Profile 5.2" };
}

bool PreferHighThroughputVideoLevel(int width, int height, int framerate) {
  if (width <= 0 || height <= 0 || framerate <= 0) {
    return false;
  }

  const uint64_t pixelsPerSecond =
    static_cast<uint64_t>(width) * static_cast<uint64_t>(height) * static_cast<uint64_t>(framerate);
  return pixelsPerSecond > (3840ULL * 2160ULL * 30ULL);
}

std::vector<VideoProfileSelection> GetVideoProfileCandidates(int videoFormat, int width, int height, int framerate) {
  const bool highThroughput = PreferHighThroughputVideoLevel(width, height, framerate);

  if (videoFormat & VIDEO_FORMAT_H264) {
    const H264ProfileSelection profile = SelectH264Profile(width, height, framerate);
    return { { profile.mimeType, profile.label } };
  }
  if (videoFormat & VIDEO_FORMAT_H265) {
    if (highThroughput) {
      return {
        { "video/mp4; codecs=\"hev1.1.6.L156.B0\"", "HEVC Main Level Profile 5.2" },
        { "video/mp4; codecs=\"hev1.1.6.L153.B0\"", "HEVC Main Level Profile 5.1" },
      };
    }
    return {
      { "video/mp4; codecs=\"hev1.1.6.L153.B0\"", "HEVC Main Level Profile 5.1" },
      { "video/mp4; codecs=\"hev1.1.6.L156.B0\"", "HEVC Main Level Profile 5.2" },
    };
  }
  if (videoFormat & VIDEO_FORMAT_H265_MAIN10) {
    if (highThroughput) {
      return {
        { "video/mp4; codecs=\"hev1.2.4.L156.B0\"", "HEVC Main10 Level Profile 5.2" },
        { "video/mp4; codecs=\"hev1.2.4.L153.B0\"", "HEVC Main10 Level Profile 5.1" },
      };
    }
    return {
      { "video/mp4; codecs=\"hev1.2.4.L153.B0\"", "HEVC Main10 Level Profile 5.1" },
      { "video/mp4; codecs=\"hev1.2.4.L156.B0\"", "HEVC Main10 Level Profile 5.2" },
    };
  }
  if (videoFormat & VIDEO_FORMAT_AV1_MAIN8) {
    if (highThroughput) {
      return {
        { "video/mp4; codecs=\"av01.0.14M.08\"", "AV1 Main Level Profile 5.2" },
        { "video/mp4; codecs=\"av01.0.15M.08\"", "AV1 Main Level Profile 5.3" },
        { "video/mp4; codecs=\"av01.0.16M.08\"", "AV1 Main Level Profile 6.0" },
        { "video/mp4; codecs=\"av01.0.17M.08\"", "AV1 Main Level Profile 6.1" },
        { "video/mp4; codecs=\"av01.0.18M.08\"", "AV1 Main Level Profile 6.2" },
        { "video/mp4; codecs=\"av01.0.19M.08\"", "AV1 Main Level Profile 6.3" },
        { "video/mp4; codecs=\"av01.0.13M.08\"", "AV1 Main Level Profile 5.1" },
      };
    }
    return {
      { "video/mp4; codecs=\"av01.0.13M.08\"", "AV1 Main Level Profile 5.1" },
      { "video/mp4; codecs=\"av01.0.14M.08\"", "AV1 Main Level Profile 5.2" },
      { "video/mp4; codecs=\"av01.0.15M.08\"", "AV1 Main Level Profile 5.3" },
      { "video/mp4; codecs=\"av01.0.16M.08\"", "AV1 Main Level Profile 6.0" },
      { "video/mp4; codecs=\"av01.0.17M.08\"", "AV1 Main Level Profile 6.1" },
      { "video/mp4; codecs=\"av01.0.18M.08\"", "AV1 Main Level Profile 6.2" },
      { "video/mp4; codecs=\"av01.0.19M.08\"", "AV1 Main Level Profile 6.3" },
    };
  }
  if (videoFormat & VIDEO_FORMAT_AV1_MAIN10) {
    if (highThroughput) {
      return {
        { "video/mp4; codecs=\"av01.0.14M.10\"", "AV1 Main10 Level Profile 5.2" },
        { "video/mp4; codecs=\"av01.0.15M.10\"", "AV1 Main10 Level Profile 5.3" },
        { "video/mp4; codecs=\"av01.0.16M.10\"", "AV1 Main10 Level Profile 6.0" },
        { "video/mp4; codecs=\"av01.0.17M.10\"", "AV1 Main10 Level Profile 6.1" },
        { "video/mp4; codecs=\"av01.0.18M.10\"", "AV1 Main10 Level Profile 6.2" },
        { "video/mp4; codecs=\"av01.0.19M.10\"", "AV1 Main10 Level Profile 6.3" },
        { "video/mp4; codecs=\"av01.0.13M.10\"", "AV1 Main10 Level Profile 5.1" },
      };
    }
    return {
      { "video/mp4; codecs=\"av01.0.13M.10\"", "AV1 Main10 Level Profile 5.1" },
      { "video/mp4; codecs=\"av01.0.14M.10\"", "AV1 Main10 Level Profile 5.2" },
      { "video/mp4; codecs=\"av01.0.15M.10\"", "AV1 Main10 Level Profile 5.3" },
      { "video/mp4; codecs=\"av01.0.16M.10\"", "AV1 Main10 Level Profile 6.0" },
      { "video/mp4; codecs=\"av01.0.17M.10\"", "AV1 Main10 Level Profile 6.1" },
      { "video/mp4; codecs=\"av01.0.18M.10\"", "AV1 Main10 Level Profile 6.2" },
      { "video/mp4; codecs=\"av01.0.19M.10\"", "AV1 Main10 Level Profile 6.3" },
    };
  }

  return {};
}

VideoProfileSelection SelectVideoProfile(int videoFormat, int width, int height, int framerate) {
  std::vector<VideoProfileSelection> candidates = GetVideoProfileCandidates(videoFormat, width, height, framerate);
  if (!candidates.empty()) {
    return candidates.front();
  }
  return { nullptr, nullptr };
}

bool ServerSupportsCodecMode(int serverCodecModeSupport, int serverCodecMode) {
  if (serverCodecMode == SCM_H264) {
    return true;
  }
  return (serverCodecModeSupport & serverCodecMode) != 0;
}

bool IsDuplicateVideoFormat(const std::vector<VideoFormatCandidate>& candidates, int videoFormat) {
  for (const VideoFormatCandidate& candidate : candidates) {
    if (candidate.videoFormat == videoFormat) {
      return true;
    }
  }
  return false;
}

void AddVideoFormatCandidate(
  std::vector<VideoFormatCandidate>& candidates,
  const std::string& codec,
  bool hdr,
  int serverCodecModeSupport) {
  VideoFormatCandidate candidate;

  if (codec == "AV1") {
    candidate = hdr
      ? VideoFormatCandidate { "AV1", true, VIDEO_FORMAT_AV1_MAIN10, SCM_AV1_MAIN10 }
      : VideoFormatCandidate { "AV1", false, VIDEO_FORMAT_AV1_MAIN8, SCM_AV1_MAIN8 };
  } else if (codec == "HEVC") {
    candidate = hdr
      ? VideoFormatCandidate { "HEVC", true, VIDEO_FORMAT_H265_MAIN10, SCM_HEVC_MAIN10 }
      : VideoFormatCandidate { "HEVC", false, VIDEO_FORMAT_H265, SCM_HEVC };
  } else if (codec == "H264" && !hdr) {
    candidate = { "H264", false, VIDEO_FORMAT_H264, SCM_H264 };
  } else {
    MoonlightInstance::ClLogMessage("Video codec probe candidate skipped: codec=%s, hdr=%d, reason=unsupported codec/hdr combination\n",
      codec.c_str(), hdr);
    return;
  }

  if (!ServerSupportsCodecMode(serverCodecModeSupport, candidate.serverCodecMode)) {
    MoonlightInstance::ClLogMessage("Video codec probe candidate skipped: codec=%s, hdr=%d, format=0x%x, serverCodecMode=0x%x, serverCodecModeSupport=0x%x, reason=host does not advertise codec mode\n",
      candidate.codec, candidate.hdr, candidate.videoFormat, candidate.serverCodecMode, serverCodecModeSupport);
    return;
  }
  if (IsDuplicateVideoFormat(candidates, candidate.videoFormat)) {
    MoonlightInstance::ClLogMessage("Video codec probe candidate skipped: codec=%s, hdr=%d, format=0x%x, reason=duplicate candidate\n",
      candidate.codec, candidate.hdr, candidate.videoFormat);
    return;
  }

  MoonlightInstance::ClLogMessage("Video codec probe candidate queued: codec=%s, hdr=%d, format=0x%x, serverCodecMode=0x%x\n",
    candidate.codec, candidate.hdr, candidate.videoFormat, candidate.serverCodecMode);
  candidates.push_back(candidate);
}

std::vector<VideoFormatCandidate> BuildVideoFormatProbeOrder(
  const std::string& preferredCodec,
  bool hdrMode,
  int serverCodecModeSupport) {
  std::vector<VideoFormatCandidate> candidates;

  if (hdrMode) {
    AddVideoFormatCandidate(candidates, preferredCodec, true, serverCodecModeSupport);
    AddVideoFormatCandidate(candidates, "HEVC", true, serverCodecModeSupport);
    AddVideoFormatCandidate(candidates, "AV1", true, serverCodecModeSupport);
    AddVideoFormatCandidate(candidates, preferredCodec, false, serverCodecModeSupport);
  } else {
    AddVideoFormatCandidate(candidates, preferredCodec, false, serverCodecModeSupport);
  }

  AddVideoFormatCandidate(candidates, "AV1", false, serverCodecModeSupport);
  AddVideoFormatCandidate(candidates, "HEVC", false, serverCodecModeSupport);
  AddVideoFormatCandidate(candidates, "H264", false, serverCodecModeSupport);

  return candidates;
}

void AppendJsonString(std::ostringstream& json, const std::string& value) {
  json << '"';
  for (char ch : value) {
    switch (ch) {
      case '"':
        json << "\\\"";
        break;
      case '\\':
        json << "\\\\";
        break;
      case '\n':
        json << "\\n";
        break;
      case '\r':
        json << "\\r";
        break;
      case '\t':
        json << "\\t";
        break;
      default:
        json << ch;
        break;
    }
  }
  json << '"';
}

bool IsMimeTypeDisabled(const std::string& disabledMimeTypes, const char* mimeType) {
  if (disabledMimeTypes.empty() || mimeType == nullptr || mimeType[0] == '\0') {
    return false;
  }

  std::string disabledList = "\n";
  disabledList += disabledMimeTypes;
  disabledList += "\n";

  std::string needle = "\n";
  needle += mimeType;
  needle += "\n";

  return disabledList.find(needle) != std::string::npos;
}

int CountDisabledMimeTypes(const std::string& disabledMimeTypes) {
  if (disabledMimeTypes.empty()) {
    return 0;
  }

  int count = 1;
  for (char ch : disabledMimeTypes) {
    if (ch == '\n') {
      count++;
    }
  }
  return count;
}

const char* CodecNameForVideoFormat(int videoFormat) {
  if (videoFormat & (VIDEO_FORMAT_AV1_MAIN8 | VIDEO_FORMAT_AV1_MAIN10)) {
    return "AV1";
  }
  if (videoFormat & (VIDEO_FORMAT_H265 | VIDEO_FORMAT_H265_MAIN10)) {
    return "HEVC";
  }
  if (videoFormat & VIDEO_FORMAT_H264) {
    return "H264";
  }
  return "UNKNOWN";
}

bool IsHdrVideoFormat(int videoFormat) {
  return (videoFormat & (VIDEO_FORMAT_H265_MAIN10 | VIDEO_FORMAT_AV1_MAIN10)) != 0;
}

void PostCodecProfileResult(
  int videoFormat,
  int width,
  int height,
  int fps,
  int profileIndex,
  const VideoProfileSelection& profile,
  bool supported,
  bool skipped,
  const char* skipReason,
  bool selected) {
  std::ostringstream message;

  message << "CodecProfileResult: {";
  message << "\"source\":\"streamSetup\"";
  message << ",\"codec\":";
  AppendJsonString(message, CodecNameForVideoFormat(videoFormat));
  message << ",\"hdr\":" << (IsHdrVideoFormat(videoFormat) ? "true" : "false");
  message << ",\"videoFormat\":" << videoFormat;
  message << ",\"profileIndex\":" << profileIndex;
  message << ",\"profile\":";
  AppendJsonString(message, profile.label ? profile.label : "");
  message << ",\"mimeType\":";
  AppendJsonString(message, profile.mimeType ? profile.mimeType : "");
  message << ",\"supported\":" << (supported ? "true" : "false");
  message << ",\"skipped\":" << (skipped ? "true" : "false");
  message << ",\"skipReason\":";
  AppendJsonString(message, skipReason ? skipReason : "");
  message << ",\"selected\":" << (selected ? "true" : "false");
  message << ",\"width\":" << width;
  message << ",\"height\":" << height;
  message << ",\"fps\":" << fps;
  message << "}";

  PostToJs(message.str());
}

}

MoonlightInstance::SourceListener::SourceListener(
  MoonlightInstance* instance
) : m_Instance(instance) {}

void MoonlightInstance::SourceListener::OnSourceOpen() {
  ClLogMessage("EMSS::OnOpen (source ready)\n");
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_EmssReadyState = EmssReadyState::kOpen;
  m_Instance->m_EmssStateChanged.notify_all();
}

void MoonlightInstance::SourceListener::OnSourceOpenPending() {
  ClLogMessage("EMSS::OnOpenPending (source opening)\n");
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_EmssReadyState = EmssReadyState::kOpenPending;
  m_Instance->m_EmssStateChanged.notify_all();
}

void MoonlightInstance::SourceListener::OnSourceClosed() {
  ClLogMessage("EMSS::OnClosed (source detached/closed)\n");
  {
    std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
    m_Instance->m_EmssReadyState = EmssReadyState::kClosed;
    m_Instance->m_EmssStateChanged.notify_all();
  }
  if (m_Instance->m_SyntheticAudioTestState.load() == SyntheticAudioTestState::Binding) {
    m_Instance->ConfigureSyntheticAudioTest();
  }
}

MoonlightInstance::VideoTrackListener::VideoTrackListener(
  MoonlightInstance* instance
) : m_Instance(instance) {}

void MoonlightInstance::VideoTrackListener::OnTrackOpen() {
  ClLogMessage("VIDEO ElementaryMediaTrack::OnTrackOpen (sessionId=%u)\n",
    static_cast<unsigned int>(m_Instance->m_VideoSessionId.load()));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_VideoStarted = true;
  m_Instance->m_EmssVideoStateChanged.notify_all();
  LiRequestIdrFrame();
}

void MoonlightInstance::VideoTrackListener::OnTrackClosed(samsung::wasm::ElementaryMediaTrack::CloseReason reason) {
  ClLogMessage("VIDEO ElementaryMediaTrack::OnTrackClosed (reason=%d, sessionId=%u)\n",
    static_cast<int>(reason), static_cast<unsigned int>(m_Instance->m_VideoSessionId.load()));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_VideoStarted = false;
}

void MoonlightInstance::VideoTrackListener::OnSessionIdChanged(samsung::wasm::SessionId new_session_id) {
  ClLogMessage("VIDEO ElementaryMediaTrack::OnSessionIdChanged: old=%u, new=%u\n",
    static_cast<unsigned int>(m_Instance->m_VideoSessionId.load()),
    static_cast<unsigned int>(new_session_id));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_VideoSessionId.store(new_session_id);
}

MoonlightInstance::AudioTrackListener::AudioTrackListener(
  MoonlightInstance* instance
) : m_Instance(instance) {}

void MoonlightInstance::AudioTrackListener::OnTrackOpen() {
  ClLogMessage("AUDIO ElementaryMediaTrack::OnTrackOpen (sessionId=%u)\n",
    static_cast<unsigned int>(m_Instance->m_AudioSessionId.load()));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_AudioStarted = true;
  m_Instance->m_EmssAudioStateChanged.notify_all();
}

void MoonlightInstance::AudioTrackListener::OnTrackClosed(samsung::wasm::ElementaryMediaTrack::CloseReason reason) {
  ClLogMessage("AUDIO ElementaryMediaTrack::OnTrackClosed (reason=%d, sessionId=%u)\n",
    static_cast<int>(reason), static_cast<unsigned int>(m_Instance->m_AudioSessionId.load()));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_AudioStarted = false;
  m_Instance->m_EmssAudioStateChanged.notify_all();
}

void MoonlightInstance::AudioTrackListener::OnSessionIdChanged(samsung::wasm::SessionId new_session_id) {
  ClLogMessage("AUDIO ElementaryMediaTrack::OnSessionIdChanged: old=%u, new=%u\n",
    static_cast<unsigned int>(m_Instance->m_AudioSessionId.load()),
    static_cast<unsigned int>(new_session_id));
  std::unique_lock<std::mutex> lock(m_Instance->m_Mutex);
  m_Instance->m_AudioSessionId.store(new_session_id);
}

void MoonlightInstance::AudioTrackListener::OnAppendError(samsung::wasm::OperationResult result) {
  ClLogMessage("AUDIO ElementaryMediaTrack::OnAppendError: result=%d, sessionId=%u\n",
    static_cast<int>(result), static_cast<unsigned int>(m_Instance->m_AudioSessionId.load()));
}

MoonlightInstance::SyntheticAudioTrackListener::SyntheticAudioTrackListener(
  MoonlightInstance* instance
) : m_Instance(instance) {}

void MoonlightInstance::SyntheticAudioTrackListener::OnTrackOpen() {
  if (m_Instance->m_SyntheticAudioTestState.load() != SyntheticAudioTestState::Opening) {
    ClLogMessage("Ignoring stale synthetic PCM OnTrackOpen callback\n");
    return;
  }
  ClLogMessage("SYNTHETIC AUDIO ElementaryMediaTrack::OnTrackOpen (sessionId=%u)\n",
    static_cast<unsigned int>(m_Instance->m_SyntheticAudioSessionId.load()));
  m_Instance->m_SyntheticAudioTestState.store(SyntheticAudioTestState::Ready);
  m_Instance->LogEmssAudioClock(
    "synthetic-dialog-ready",
    static_cast<double>(m_Instance->m_SyntheticAudioSampleCursor) / 48000.0);
}

void MoonlightInstance::SyntheticAudioTrackListener::OnTrackClosed(
  samsung::wasm::ElementaryMediaTrack::CloseReason reason) {
  ClLogMessage("SYNTHETIC AUDIO ElementaryMediaTrack::OnTrackClosed (reason=%d, sessionId=%u)\n",
    static_cast<int>(reason),
    static_cast<unsigned int>(m_Instance->m_SyntheticAudioSessionId.load()));
  SyntheticAudioTestState state = m_Instance->m_SyntheticAudioTestState.load();
  if (state == SyntheticAudioTestState::Opening || state == SyntheticAudioTestState::Ready) {
    m_Instance->m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
  }
}

void MoonlightInstance::SyntheticAudioTrackListener::OnSessionIdChanged(
  samsung::wasm::SessionId newSessionId) {
  ClLogMessage("SYNTHETIC AUDIO ElementaryMediaTrack::OnSessionIdChanged: old=%u, new=%u\n",
    static_cast<unsigned int>(m_Instance->m_SyntheticAudioSessionId.load()),
    static_cast<unsigned int>(newSessionId));
  m_Instance->m_SyntheticAudioSessionId.store(newSessionId);
}

void MoonlightInstance::SyntheticAudioTrackListener::OnAppendError(
  samsung::wasm::OperationResult result) {
  ClLogMessage("SYNTHETIC AUDIO ElementaryMediaTrack::OnAppendError: result=%d, sessionId=%u\n",
    static_cast<int>(result),
    static_cast<unsigned int>(m_Instance->m_SyntheticAudioSessionId.load()));
}

const char* MoonlightInstance::EmssLatencyModeName(
  samsung::wasm::ElementaryMediaStreamSource::LatencyMode mode) {
  switch (mode) {
    case samsung::wasm::ElementaryMediaStreamSource::LatencyMode::kNormal:
      return "normal";
    case samsung::wasm::ElementaryMediaStreamSource::LatencyMode::kLow:
      return "low";
    case samsung::wasm::ElementaryMediaStreamSource::LatencyMode::kUltraLow:
      return "ultra-low";
    default:
      return "unknown";
  }
}

void MoonlightInstance::LogEmssAudioClock(const char* context, double audioPts) const {
  const char* actualModeName = "unavailable";
  int modeResultCode = -1;
  if (m_Source) {
    auto modeResult = m_Source->GetLatencyMode();
    modeResultCode = static_cast<int>(modeResult.operation_result);
    if (modeResult) {
      actualModeName = EmssLatencyModeName(*modeResult);
    }
  }

  auto mediaTimeResult = m_MediaElement.GetCurrentTime();
  if (mediaTimeResult) {
    ClLogMessage(
      "EMSS audio clock: context=%s, actualMode=%s, audioPts=%.6f, mediaTime=%.6f, modeResult=%d\n",
      context, actualModeName, audioPts, (*mediaTimeResult).count(), modeResultCode);
  } else {
    ClLogMessage(
      "EMSS audio clock: context=%s, actualMode=%s, audioPts=%.6f, mediaTime=unavailable, modeResult=%d, mediaTimeResult=%d\n",
      context, actualModeName, audioPts, modeResultCode,
      static_cast<int>(mediaTimeResult.operation_result));
  }
}

void MoonlightInstance::ResetSyntheticAudioTestMedia() {
  m_SyntheticAudioTestState.store(SyntheticAudioTestState::Stopping);
  m_MediaElement.Pause();
  if (m_Source) {
    m_MediaElement.SetSrc(nullptr);
  }
  m_AudioTrack = samsung::wasm::ElementaryMediaTrack();
  m_VideoTrack = samsung::wasm::ElementaryMediaTrack();
  m_SyntheticAudioTrack = samsung::wasm::ElementaryMediaTrack();
  m_Source.reset();
  m_AudioStarted.store(false);
  m_VideoStarted.store(false);
  m_AudioSessionId.store(0);
  m_VideoSessionId.store(0);
  m_SyntheticAudioSessionId.store(0);
  m_EmssReadyState = EmssReadyState::kDetached;
  m_SyntheticAudioSampleCursor = 0;
  m_SyntheticAudioClickCount = 0;
  m_SyntheticAudioTestState.store(SyntheticAudioTestState::Inactive);
}

MessageResult MoonlightInstance::StartSyntheticAudioTest(bool gameMode) {
  JoinStaleThreadsIfIdle();
  if (GetLifecycle() != StreamLifecycle::Idle) {
    return MessageResult::Reject(emscripten::val(
      std::string("Synthetic audio test is unavailable while a stream is active.")));
  }

  ResetSyntheticAudioTestMedia();
  m_SyntheticAudioTestState.store(SyntheticAudioTestState::Binding);

  constexpr int kSampleRate = 48000;
  constexpr int kChannelCount = 2;
  constexpr int kPacketFrames = 960;
  constexpr int kNoiseFrames = 240;
  m_SyntheticAudioClick.assign(kPacketFrames * kChannelCount, 0);
  uint32_t noise = 0x13579bdfu;
  for (int frame = 0; frame < kNoiseFrames; frame++) {
    noise ^= noise << 13;
    noise ^= noise >> 17;
    noise ^= noise << 5;
    const int centered = static_cast<int>(noise & 0xffffu) - 32768;
    const int sample = static_cast<int>(
      (static_cast<int64_t>(centered) * (kNoiseFrames - frame) * 4) /
      (kNoiseFrames * 5));
    m_SyntheticAudioClick[frame * 2] = static_cast<opus_int16>(sample);
    m_SyntheticAudioClick[frame * 2 + 1] = static_cast<opus_int16>(sample);
  }

  const EmssLatencyMode selectedMode = gameMode
    ? EmssLatencyMode::kUltraLow
    : EmssLatencyMode::kLow;
  m_Source = std::make_unique<samsung::wasm::ElementaryMediaStreamSource>(
    selectedMode,
    EmssRenderingMode::kMediaElement);
  if (!m_Source->IsValid()) {
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    return MessageResult::Reject(emscripten::val(
      std::string("Unable to create the synthetic PCM EMSS source.")));
  }
  auto listenerResult = m_Source->SetListener(&m_SourceListener);
  if (!listenerResult) {
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    return MessageResult::Reject(emscripten::val(
      std::string("Unable to attach the synthetic PCM EMSS listener.")));
  }

  // This is deliberately emitted before SetSrc(), so it precedes the Flutter
  // dialog and records the mode actually reported by the EMSS object.
  LogEmssAudioClock("before-synthetic-dialog", 0.0);
  auto sourceResult = m_MediaElement.SetSrc(m_Source.get());
  if (!sourceResult) {
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    return MessageResult::Reject(emscripten::val(
      std::string("Unable to bind the synthetic PCM EMSS source.")));
  }

  ClLogMessage(
    "Synthetic PCM click test requested: gameMode=%d, sampleRate=%d, channels=%d, packetFrames=%d, networkBypassed=1, opusBypassed=1, moonlightQueuesBypassed=1\n",
    gameMode, kSampleRate, kChannelCount, kPacketFrames);
  return MessageResult::Resolve();
}

void MoonlightInstance::ConfigureSyntheticAudioTest() {
  if (m_SyntheticAudioTestState.load() != SyntheticAudioTestState::Binding || !m_Source) {
    return;
  }

  constexpr int kSampleRate = 48000;
  auto trackResult = m_Source->AddTrack(
    samsung::wasm::ElementaryAudioTrackConfig {
      "audio/webm; codecs=\"pcm\"",
      {},
      samsung::wasm::DecodingMode::kHardware,
      samsung::wasm::SampleFormat::kS16,
      samsung::wasm::ChannelLayout::kStereo,
      kSampleRate,
    });
  if (!trackResult) {
    ClLogMessage("Synthetic PCM AddTrack failed: result=%d\n",
      static_cast<int>(trackResult.operation_result));
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    return;
  }

  m_SyntheticAudioTrack = std::move(*trackResult);
  auto listenerResult = m_SyntheticAudioTrack.SetListener(&m_SyntheticAudioTrackListener);
  if (!listenerResult) {
    ClLogMessage("Synthetic PCM track listener failed: result=%d\n",
      static_cast<int>(listenerResult.operation_result));
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    return;
  }

  m_SyntheticAudioTestState.store(SyntheticAudioTestState::Opening);
  auto openResult = m_Source->Open([this](EmssOperationResult result) {
    if (m_SyntheticAudioTestState.load() != SyntheticAudioTestState::Opening) {
      ClLogMessage("Ignoring stale synthetic PCM Open callback: result=%d\n",
        static_cast<int>(result));
      return;
    }
    if (result != EmssOperationResult::kSuccess) {
      ClLogMessage("Synthetic PCM source Open callback failed: result=%d\n",
        static_cast<int>(result));
      m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
      return;
    }
    ClLogMessage("Synthetic PCM source opened; requesting playback\n");
    auto playResult = m_MediaElement.Play([this](EmssOperationResult playResult) {
      SyntheticAudioTestState state = m_SyntheticAudioTestState.load();
      if (state != SyntheticAudioTestState::Opening && state != SyntheticAudioTestState::Ready) {
        ClLogMessage("Ignoring stale synthetic PCM Play callback: result=%d\n",
          static_cast<int>(playResult));
        return;
      }
      ClLogMessage("Synthetic PCM Play callback: result=%d, ready=%d\n",
        static_cast<int>(playResult),
        m_SyntheticAudioTestState.load() == SyntheticAudioTestState::Ready);
      if (playResult != EmssOperationResult::kSuccess) {
        m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
      }
    });
    if (!playResult) {
      ClLogMessage("Synthetic PCM Play request failed: result=%d\n",
        static_cast<int>(playResult.operation_result));
      m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
    }
  });
  if (!openResult) {
    ClLogMessage("Synthetic PCM Open request failed: result=%d\n",
      static_cast<int>(openResult.operation_result));
    m_SyntheticAudioTestState.store(SyntheticAudioTestState::Failed);
  }
}

MessageResult MoonlightInstance::PlaySyntheticAudioClick(std::string inputLabel) {
  SyntheticAudioTestState state = m_SyntheticAudioTestState.load();
  if (state != SyntheticAudioTestState::Ready) {
    const char* reason = state == SyntheticAudioTestState::Failed
      ? "Synthetic PCM audio initialization failed."
      : "Synthetic PCM audio is still initializing; press again.";
    return MessageResult::Reject(emscripten::val(std::string(reason)));
  }

  constexpr int kSampleRate = 48000;
  constexpr int kPacketFrames = 960;
  const double audioPts = static_cast<double>(m_SyntheticAudioSampleCursor) / kSampleRate;
  const uint32_t clickNumber = ++m_SyntheticAudioClickCount;
  LogEmssAudioClock("synthetic-click-before-append", audioPts);
  ClLogMessage(
    "Synthetic PCM click append: click=%u, input=%s, wallClockMs=%llu, audioPts=%.6f, sessionId=%u, frames=%d\n",
    clickNumber, inputLabel.c_str(), static_cast<unsigned long long>(LiGetMillis()),
    audioPts, static_cast<unsigned int>(m_SyntheticAudioSessionId.load()), kPacketFrames);

  samsung::wasm::ElementaryMediaPacket packet {
    TimeStamp(audioPts),
    TimeStamp(audioPts),
    TimeStamp(static_cast<double>(kPacketFrames) / kSampleRate),
    true,
    m_SyntheticAudioClick.size() * sizeof(opus_int16),
    m_SyntheticAudioClick.data(),
    0,
    0,
    0,
    0,
    m_SyntheticAudioSessionId.load(),
  };
  auto result = m_SyntheticAudioTrack.AppendPacketAsync(packet);
  if (!result) {
    ClLogMessage("Synthetic PCM click append failed: click=%u, result=%d\n",
      clickNumber, static_cast<int>(result.operation_result));
    return MessageResult::Reject(emscripten::val(
      std::string("The TV rejected the synthetic PCM click packet.")));
  }
  m_SyntheticAudioSampleCursor += kPacketFrames;
  return MessageResult::Resolve(emscripten::val(clickNumber));
}

MessageResult MoonlightInstance::StopSyntheticAudioTest() {
  SyntheticAudioTestState state = m_SyntheticAudioTestState.load();
  if (state == SyntheticAudioTestState::Inactive) {
    return MessageResult::Resolve();
  }
  ClLogMessage("Stopping synthetic PCM click test: state=%d, clicks=%u\n",
    static_cast<int>(state), m_SyntheticAudioClickCount);
  ResetSyntheticAudioTestMedia();
  return MessageResult::Resolve();
}

void MoonlightInstance::DidChangeFocus(bool got_focus) {
  // Request an IDR frame to dump the frame queue that may have
  // built up from the GL pipeline being stalled.
  if (got_focus) {
    LiRequestIdrFrame();
  }
}

bool MoonlightInstance::InitializeRenderingSurface(int width, int height) {
  return true;
}

int MoonlightInstance::StartupVidDecSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags) {
  ClLogMessage("Video startup setup: format=0x%x, width=%d, height=%d, fps=%d, drFlags=0x%x, source=%d, videoStarted=%d\n",
    videoFormat, width, height, redrawRate, drFlags, g_Instance->m_Source ? 1 : 0,
    g_Instance->m_VideoStarted.load());
  ClLogMessage("Video: binding source to element\n");
  g_Instance->m_MediaElement.SetSrc(g_Instance->m_Source.get());

  ClLogMessage("Video: waiting for source closed state before adding track\n");
  if (!g_Instance->WaitFor(&g_Instance->m_EmssStateChanged, "source closed before AddTrack", kEmssSourceStateTimeoutMs, [] {
    return g_Instance->m_EmssReadyState == EmssReadyState::kClosed;
  })) {
    return -1;
  }
  ClLogMessage("Video: source closed, adding track\n");

  if (g_Instance->m_AudioBackend == AudioBackend::NativeEmss) {
    // moonlight-common starts the video renderer before the audio renderer's
    // init callback. The selected stream configuration is already final here,
    // and all supported Opus configurations negotiate at 48 kHz.
    const int channelCount = CHANNEL_COUNT_FROM_AUDIO_CONFIGURATION(g_Instance->m_AudioConfig);
    const int sampleRate = 48000;
    samsung::wasm::ChannelLayout channelLayout = samsung::wasm::ChannelLayout::kUnsupported;
    switch (channelCount) {
      case 2:
        channelLayout = samsung::wasm::ChannelLayout::kStereo;
        break;
      case 6:
        channelLayout = samsung::wasm::ChannelLayout::k5_1Back;
        break;
      case 8:
        channelLayout = samsung::wasm::ChannelLayout::k7_1;
        break;
      default:
        ClLogMessage("Native audio: unsupported channel count %d\n", channelCount);
        return -1;
    }

    if (sampleRate <= 0) {
      ClLogMessage("Native audio: invalid negotiated sample rate %d\n", sampleRate);
      return -1;
    }

    g_Instance->m_AudioChannelCount.store(channelCount);
    g_Instance->m_AudioSampleRate.store(sampleRate);

    auto addAudioTrackResult = g_Instance->m_Source->AddTrack(
      samsung::wasm::ElementaryAudioTrackConfig {
        "audio/webm; codecs=\"pcm\"",
        {},
        samsung::wasm::DecodingMode::kHardware,
        samsung::wasm::SampleFormat::kS16,
        channelLayout,
        static_cast<uint32_t>(sampleRate),
      }
    );
    if (!addAudioTrackResult) {
      ClLogMessage("Native audio: AddTrack failed: result=%d, sampleRate=%d, channels=%d\n",
        static_cast<int>(addAudioTrackResult.operation_result), sampleRate, channelCount);
      PostToJs("ProgressMsg: Native audio is unavailable; switch Audio backend to Web Audio.");
      return -1;
    }

    g_Instance->m_AudioTrack = std::move(*addAudioTrackResult);
    auto listenerResult = g_Instance->m_AudioTrack.SetListener(&g_Instance->m_AudioTrackListener);
    if (!listenerResult) {
      ClLogMessage("Native audio: SetListener failed: result=%d\n",
        static_cast<int>(listenerResult.operation_result));
      return -1;
    }
    ClLogMessage("Native audio track configured: sampleRate=%d, channels=%d\n", sampleRate, channelCount);
  }

  {
    std::vector<VideoProfileSelection> profiles = GetVideoProfileCandidates(videoFormat, width, height, redrawRate);
    if (profiles.empty()) {
      ClLogMessage("Failed to select video codec profile candidates (videoFormat=0x%x)\n", videoFormat);
      return -1;
    }

    PostToJs("ProgressMsg: Checking TV codec profile...");
    bool selectedProfile = false;
    int profileIndex = 0;

    for (const VideoProfileSelection& profile : profiles) {
      const char* mimetype = profile.mimeType;
      const char* profileLabel = profile.label;

      if (IsMimeTypeDisabled(g_Instance->m_DisabledVideoMimeTypes, mimetype)) {
        ClLogMessage("Video codec profile skipped by user: index=%d, profile=%s, mimeType=%s\n",
          profileIndex, profileLabel, mimetype);
        PostCodecProfileResult(videoFormat, width, height, redrawRate, profileIndex, profile, false, true, "disabledByUser", false);
        profileIndex++;
        continue;
      }

      ClLogMessage("Video codec profile attempt: index=%d, profile=%s, mimeType=%s\n",
        profileIndex, profileLabel, mimetype);

      auto add_track_result = g_Instance->m_Source->AddTrack(
        samsung::wasm::ElementaryVideoTrackConfig {
          mimetype, // MIME-type: Selected Video Format
          {}, // Extradata: Empty
          samsung::wasm::DecodingMode::kHardware, // Decoding mode: Hardware
          static_cast<uint32_t>(width), // Video resolution: Width
          static_cast<uint32_t>(height), // Video resolution: Height
          static_cast<uint32_t>(redrawRate), // Framerate: Numerator
          1, // Framerate: Denominator
        }
      );
      if (add_track_result) {
        ClLogMessage("Video codec profile selected: index=%d, profile=%s, mimeType=%s\n",
          profileIndex, profileLabel, mimetype);
        PostCodecProfileResult(videoFormat, width, height, redrawRate, profileIndex, profile, true, false, "", true);
        g_Instance->m_VideoTrack = std::move(*add_track_result);
        g_Instance->m_VideoTrack.SetListener(&g_Instance->m_VideoTrackListener);
        selectedProfile = true;
        break;
      }

      ClLogMessage("Video: AddTrack failed for profile index=%d, profile=%s, mimeType=%s, width=%d, height=%d, fps=%d\n",
        profileIndex, profileLabel, mimetype, width, height, redrawRate);
      PostCodecProfileResult(videoFormat, width, height, redrawRate, profileIndex, profile, false, false, "", false);
      profileIndex++;
    }

    if (!selectedProfile) {
      ClLogMessage("Video: AddTrack failed for every enabled codec profile: videoFormat=0x%x, width=%d, height=%d, fps=%d, disabledMimeTypes=%d\n",
        videoFormat, width, height, redrawRate, CountDisabledMimeTypes(g_Instance->m_DisabledVideoMimeTypes));
      return -1;
    }
  }

  ClLogMessage("Video: opening source\n");
  g_Instance->m_Source->Open([](EmssOperationResult result) {
    ClLogMessage("Video: source open callback result=%d\n", static_cast<int>(result));
  });
  ClLogMessage("Video: waiting for source open-pending/open state\n");
  if (!g_Instance->WaitFor(&g_Instance->m_EmssStateChanged, "source open pending/open", kEmssSourceStateTimeoutMs, [] {
    return g_Instance->m_EmssReadyState == EmssReadyState::kOpenPending ||
      g_Instance->m_EmssReadyState == EmssReadyState::kOpen;
  })) {
    return -1;
  }

  const uint32_t playAttemptId = g_Instance->GetStreamAttemptId();
  ClLogMessage("Video: source ready, calling Play (attemptId=%u, videoStarted=%d)\n",
    playAttemptId, g_Instance->m_VideoStarted.load());
  auto playState = std::make_shared<AsyncOperationWait>();
  g_Instance->m_MediaElement.Play([playState, playAttemptId](EmssOperationResult err) {
    if (err != EmssOperationResult::kSuccess) {
      ClLogMessage("Video: Play callback returned error: result=%d, callbackAttemptId=%u, currentAttemptId=%u, videoStarted=%d\n",
        static_cast<int>(err), playAttemptId, g_Instance->GetStreamAttemptId(),
        g_Instance->m_VideoStarted.load());
    } else {
      ClLogMessage("Video: Play callback succeeded: callbackAttemptId=%u, currentAttemptId=%u, videoStarted=%d\n",
        playAttemptId, g_Instance->GetStreamAttemptId(), g_Instance->m_VideoStarted.load());
    }
    std::unique_lock<std::mutex> lock(playState->mutex);
    playState->done = true;
    playState->success = err == EmssOperationResult::kSuccess;
    playState->result = static_cast<int>(err);
    playState->condition.notify_all();
  });
  {
    std::unique_lock<std::mutex> lock(playState->mutex);
    if (g_Instance->m_VideoStarted.load()) {
      ClLogMessage("Video: track already open after Play request; continuing without waiting for Play callback (attemptId=%u, emssState=%s, sessionId=%u)\n",
        g_Instance->GetStreamAttemptId(), MoonlightInstance::EmssReadyStateName(g_Instance->m_EmssReadyState),
        static_cast<unsigned int>(g_Instance->m_VideoSessionId.load()));
    } else if (!playState->condition.wait_for(lock, std::chrono::milliseconds(kEmssPlayTimeoutMs), [&playState] {
      return playState->done;
    })) {
      ClLogMessage("Video: Play callback timed out after %u ms; continuing to video track wait (attemptId=%u, emssState=%s, videoStarted=%d, sessionId=%u)\n",
        kEmssPlayTimeoutMs, g_Instance->GetStreamAttemptId(),
        MoonlightInstance::EmssReadyStateName(g_Instance->m_EmssReadyState),
        g_Instance->m_VideoStarted.load(),
        static_cast<unsigned int>(g_Instance->m_VideoSessionId.load()));
    } else if (!playState->success) {
      ClLogMessage("Video: Play callback failed before track open; continuing to video track wait: result=%d, attemptId=%u\n",
        playState->result, g_Instance->GetStreamAttemptId());
    }
  }

  ClLogMessage("Waiting for video track to open\n");
  if (!g_Instance->WaitFor(&g_Instance->m_EmssVideoStateChanged, "video track open", kEmssVideoTrackTimeoutMs, [] {
    return g_Instance->m_VideoStarted.load();
  })) {
    return -1;
  }

  if (g_Instance->m_AudioBackend == AudioBackend::NativeEmss) {
    ClLogMessage("Waiting for native audio track to open\n");
    if (!g_Instance->WaitFor(&g_Instance->m_EmssAudioStateChanged, "audio track open", kEmssAudioTrackTimeoutMs, [] {
      return g_Instance->m_AudioStarted.load();
    })) {
      PostToJs("ProgressMsg: Native audio track did not open; switch Audio backend to Web Audio.");
      return -1;
    }
  }

  ClLogMessage("Media tracks started: audioBackend=%s\n",
    g_Instance->m_AudioBackend == AudioBackend::NativeEmss ? "emss" : "webaudio");
  return 0;
}

int MoonlightInstance::VidDecSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags) {
  s_VideoSetupStartMs = LiGetMillis();
  ClLogMessage("Video decoding setup has started.\n");

  // Resize the decode buffer based on initial decode buffer length
  s_DecodeBuffer.resize(INITIAL_DECODE_BUFFER_LEN);

  // Set the video format, video resolution and video frame rate based on the input parameters
  s_VideoFormat = videoFormat;
  s_Width = width;
  s_Height = height;
  s_Framerate = redrawRate;

  // Calculate frame duration from the frame rate
  s_frameDuration = TimeStamp(1.0 / (float)redrawRate);

  // Initialize packet timestamp to zero
  s_pktPts = 0s;

  // Flag indicating whether this is the first frame of video to be decoded
  s_hasFirstFrame = false;
  s_loggedFirstDecodeUnit = false;
  s_loggedFirstAppend = false;
  s_DecodeUnitsBeforeVideoStart = 0;

  // Initialize the last second timestamp to zero
  s_lastSec = 0s;

  // Initialize the timestamp difference to zero
  s_ptsDiff = 0s;

  // Set the frame pacing flag based on instance configuration
  s_FramePacingEnabled = g_Instance->m_FramePacingEnabled;

  // Preallocate space for the performance stats string
  s_StatString.resize(1000);

  // Clear active window video statistics to start fresh
  memset(&m_ActiveWndVideoStats, 0, sizeof(m_ActiveWndVideoStats));

  // Clear last window video statistics from previous session
  memset(&m_LastWndVideoStats, 0, sizeof(m_LastWndVideoStats));

  // Reset global video statistics for new decoding session
  memset(&m_GlobalVideoStats, 0, sizeof(m_GlobalVideoStats));

  // Ensure that StartupVidDecSetup is called every time when VidDecSetup is invoked to reinitialize the media pipeline
  int initVidDec = StartupVidDecSetup(videoFormat, width, height, redrawRate, context, drFlags);

  // Check and handle errors from video decoding configuration and propagating failures
  if (initVidDec != 0) {
    ClLogMessage("Initialization of video decoding configuration failed: %d\n", initVidDec);
    return initVidDec;
  }

  return DR_OK;
}

void MoonlightInstance::VidDecCleanup(void) {
  ClLogMessage("Video decoder cleanup: setupLifetimeMs=%llu, decodeUnitsBeforeVideoStart=%u, totalBytes=%u\n",
    (unsigned long long)(s_VideoSetupStartMs ? LiGetMillis() - s_VideoSetupStartMs : 0),
    s_DecodeUnitsBeforeVideoStart, total_bytes);

  // Clear the decode buffer
  s_DecodeBuffer.clear();

  // Shrink the decode buffer to fit its contents
  s_DecodeBuffer.shrink_to_fit();
}

int MoonlightInstance::VidDecSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
  // Check if video playback has not started
  if (!g_Instance->m_VideoStarted) {
    s_DecodeUnitsBeforeVideoStart++;
    if (s_DecodeUnitsBeforeVideoStart <= 3 || (s_DecodeUnitsBeforeVideoStart % 100) == 0) {
      ClLogMessage("Video decode unit arrived before track open: count=%u, frameNumber=%d, frameType=%d, fullLength=%u\n",
        s_DecodeUnitsBeforeVideoStart, decodeUnit->frameNumber, decodeUnit->frameType,
        decodeUnit->fullLength);
    }
    return DR_OK;
  }

  if (!s_loggedFirstDecodeUnit) {
    s_loggedFirstDecodeUnit = true;
    ClLogMessage("First video decode unit accepted after %llu ms: frameNumber=%d, frameType=%d, fullLength=%u, receiveToQueueMs=%u\n",
      (unsigned long long)(s_VideoSetupStartMs ? LiGetMillis() - s_VideoSetupStartMs : 0),
      decodeUnit->frameNumber, decodeUnit->frameType, decodeUnit->fullLength,
      decodeUnit->enqueueTimeMs - decodeUnit->receiveTimeMs);
  }

  // Declare variables for entry data, offset, and total length
  PLENTRY entry;
  unsigned int offset;
  unsigned int totalLength;

  // Build one packet from multiple data chunks
  totalLength = decodeUnit->fullLength;

  // Check if the frame type from the decoding unit is IDR frame
  if (decodeUnit->frameType == FRAME_TYPE_IDR) {
    // Add some extra space in case we need to do an SPS fixup
    totalLength += MAX_SPS_EXTRA_SIZE;
  }

  // Ensure the decode buffer is large enough to hold the full packet
  if (totalLength > s_DecodeBuffer.size()) {
    // Resize decode buffer to accommodate the larger data
    s_DecodeBuffer.resize(totalLength);
  }

  // Initialize the entry pointer to the start of the buffer list
  entry = decodeUnit->bufferList;

  // Initialize the offset to 0 before starting to copy data
  offset = 0;

  // Iterate through the buffer list of video data entries
  while (entry != NULL) {
    // Copy the data of the current entry to the decode buffer at the specified offset
    memcpy(&s_DecodeBuffer[offset], entry->data, entry->length);
    // Update the offset based on the length of the copied data
    offset += entry->length;
    // Move to the next entry in the buffer list
    entry = entry->next;
  }

  // Get the current time
  auto now = std::chrono::steady_clock::now();

  // Check if this is the first video frame
  if (!s_hasFirstFrame) {
    // Record the time of the first frame
    s_firstAppend = std::chrono::steady_clock::now();
    // Update the flag to indicate that the first frame has been processed
    s_hasFirstFrame = true;
  }

  // Calculate the start of the pacing duration in milliseconds
  uint32_t pacingStart = LiGetMillis();

  // Check if the frame pacing is enabled
  if (s_FramePacingEnabled) {
    // Calculate the time elapsed since the first frame
    TimeStamp fromStart = now - s_firstAppend;
    // Wait until the packet timestamp is within the frame time margin
    while (s_pktPts > fromStart - s_ptsDiff + kFrameTimeMargin) {
      // Update the current time and recalculate the elapsed time
      now = std::chrono::steady_clock::now();
      fromStart = now - s_firstAppend;
    }
    // Synchronize packet presentation timing every time window
    if (fromStart > s_lastSec + kTimeWindow) {
      // Update the last second to the current time plus the time window
      s_lastSec += kTimeWindow;
      // Update the time difference to synchronize with the packet presentation time
      s_ptsDiff = fromStart - s_pktPts;
    }
  }

  // Calculate the end of the pacing duration in milliseconds
  uint32_t pacingEnd = LiGetMillis();

  // Measure total pacer time based on calculated pacing duration
  m_ActiveWndVideoStats.totalPacerTime += pacingEnd - pacingStart;

  // Update the timestamp of the last packet append
  s_lastTime = now;

  // Track the total number of bytes received by the decoding unit
  total_bytes += decodeUnit->fullLength;

  // Start performance stats collection if this is the first frame
  if (!m_LastFrameNumber) {
    // Record the timestamp when measurement started
    m_ActiveWndVideoStats.measurementStartTimestamp = LiGetMillis();
    m_LastFrameNumber = decodeUnit->frameNumber;
  } else {
    // Any frame number greater than the last frame number + 1 represents a dropped frame
    m_ActiveWndVideoStats.networkDroppedFrames += decodeUnit->frameNumber - (m_LastFrameNumber + 1);
    m_ActiveWndVideoStats.totalFrames += decodeUnit->frameNumber - (m_LastFrameNumber + 1);
    m_LastFrameNumber = decodeUnit->frameNumber;
  }

  // Calculate the current bitrate in bits per second and then convert the bitrate to megabits per second
  float bitrateMbps = (total_bytes * 8.0) / 1000000.0f;

  // Flip performance stats window roughly every second
  if (m_ActiveWndVideoStats.measurementStartTimestamp + 1000 < LiGetMillis()) {
    // Update performance stats overlay if it's enabled
    if (g_Instance->m_PerformanceStatsEnabled == true) {
      // Create a container to hold aggregated stats for display
      VIDEO_STATS lastTwoWndStats = {};
      // Set the bitrate field in the temporary stats for display purposes
      lastTwoWndStats.receivedBitrate = bitrateMbps;
      // Add last window and current window to the aggregated stats
      AddVideoStats(m_LastWndVideoStats, lastTwoWndStats);
      AddVideoStats(m_ActiveWndVideoStats, lastTwoWndStats);
      // Convert the aggregated stats to a display string
      FormatVideoStats(lastTwoWndStats, s_StatString.data(), s_StatString.length());
      // Send the formatted stats string to the JS frontend for overlay display
      PostToJs(std::string("StatMsg: ") + s_StatString.data());
      // Clear the stats string buffer for the next use
      std::fill(s_StatString.begin(), s_StatString.end(), 0);
      // Reset byte count for the next measurement interval
      total_bytes = 0;
    }
    // Accumulate active window stats into global stats for overall tracking
    AddVideoStats(m_ActiveWndVideoStats, m_GlobalVideoStats);
    // Move current active stats to last window stats and reset active window stats for new interval
    memcpy(&m_LastWndVideoStats, &m_ActiveWndVideoStats, sizeof(m_ActiveWndVideoStats));
    memset(&m_ActiveWndVideoStats, 0, sizeof(m_ActiveWndVideoStats));
    m_ActiveWndVideoStats.measurementStartTimestamp = LiGetMillis();
  }

  // Update min host processing latency if a valid value was provided
  if (decodeUnit->frameHostProcessingLatency != 0) {
    // Take the minimum of current min latency and new latency
    if (m_ActiveWndVideoStats.minHostProcessingLatency != 0) {
      m_ActiveWndVideoStats.minHostProcessingLatency = MIN(m_ActiveWndVideoStats.minHostProcessingLatency, decodeUnit->frameHostProcessingLatency);
    } else {
      m_ActiveWndVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
    }
    // Count how many frames included host processing latency data
    m_ActiveWndVideoStats.framesWithHostProcessingLatency += 1;
  }

  // Update max and total host processing latency
  m_ActiveWndVideoStats.maxHostProcessingLatency = MAX(m_ActiveWndVideoStats.maxHostProcessingLatency, decodeUnit->frameHostProcessingLatency);
  m_ActiveWndVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;

  // Count the received frame and increment total frames
  m_ActiveWndVideoStats.receivedFrames++;
  m_ActiveWndVideoStats.totalFrames++;

  // Create an ElementaryMediaPacket and start decoding with the decoded video data
  samsung::wasm::ElementaryMediaPacket pkt {
    s_pktPts, // presentation timestamp
    s_pktPts, // decoding timestamp
    s_frameDuration, // packet duration
    decodeUnit->frameType == FRAME_TYPE_IDR, // packet of frame type
    offset, // packet size
    s_DecodeBuffer.data(), // pointer to packet payload
    s_Width, // packet of width
    s_Height, // packet of height
    s_Framerate, // packet of framerate numerator
    1, // packet of framerate denominator
    g_Instance->m_VideoSessionId.load() // session identifier
  };

  // Track total time spent reassembling and decoding this frame
  m_ActiveWndVideoStats.totalReassemblyTime += decodeUnit->enqueueTimeMs - decodeUnit->receiveTimeMs;
  m_ActiveWndVideoStats.totalDecodeTime += LiGetMillis() - decodeUnit->enqueueTimeMs;
  m_ActiveWndVideoStats.decodedFrames++;

  // Calculate time before rendering
  uint32_t beforeRender = LiGetMillis();

  // Attempt to append the packet to the video track for rendering
  if (g_Instance->m_VideoTrack.AppendPacket(pkt)) {
    // Calculate time after rendering
    uint32_t afterRender = LiGetMillis();
    // Increment packet timestamp for next frame
    s_pktPts += s_frameDuration;
    // Track total render time and count rendered frames
    m_ActiveWndVideoStats.totalRenderTime += afterRender - beforeRender;
    m_ActiveWndVideoStats.renderedFrames++;
    if (!s_loggedFirstAppend) {
      s_loggedFirstAppend = true;
      ClLogMessage("First video packet appended after %llu ms: frameNumber=%d, keyFrame=%d, packetBytes=%u, renderCallMs=%u, sessionId=%u\n",
        (unsigned long long)(s_VideoSetupStartMs ? LiGetMillis() - s_VideoSetupStartMs : 0),
        decodeUnit->frameNumber, decodeUnit->frameType == FRAME_TYPE_IDR, offset,
        afterRender - beforeRender, static_cast<unsigned int>(g_Instance->m_VideoSessionId.load()));
    }
  } else {
    ClLogMessage("Append video packet failed: frameNumber=%d, frameType=%d, bytes=%u, sessionId=%u, videoStarted=%d\n",
      decodeUnit->frameNumber, decodeUnit->frameType, offset,
      static_cast<unsigned int>(g_Instance->m_VideoSessionId.load()),
      g_Instance->m_VideoStarted.load());
    return DR_NEED_IDR;
  }

  return DR_OK;
}

void MoonlightInstance::AddVideoStats(VIDEO_STATS& src, VIDEO_STATS& dst) {
  // Accumulate video stats from src into dst for aggregated metrics
  dst.receivedFrames += src.receivedFrames;
  dst.decodedFrames += src.decodedFrames;
  dst.renderedFrames += src.renderedFrames;
  dst.totalFrames += src.totalFrames;
  dst.networkDroppedFrames += src.networkDroppedFrames;
  dst.pacerDroppedFrames += src.pacerDroppedFrames;
  dst.totalReassemblyTime += src.totalReassemblyTime;
  dst.totalDecodeTime += src.totalDecodeTime;
  dst.totalPacerTime += src.totalPacerTime;
  dst.totalRenderTime += src.totalRenderTime;

  // Update minimum host processing latency if it's not set or if the source has a valid smaller value
  if (dst.minHostProcessingLatency == 0) {
    dst.minHostProcessingLatency = src.minHostProcessingLatency;
  } else if (src.minHostProcessingLatency != 0) {
    dst.minHostProcessingLatency = MIN(dst.minHostProcessingLatency, src.minHostProcessingLatency);
  }

  // Update the maximum host processing latency if the current source value is higher
  dst.maxHostProcessingLatency = MAX(dst.maxHostProcessingLatency, src.maxHostProcessingLatency);
  dst.totalHostProcessingLatency += src.totalHostProcessingLatency;
  dst.framesWithHostProcessingLatency += src.framesWithHostProcessingLatency;

  // Attempt to retrieve the latest estimated RTT and variance
  if (!LiGetEstimatedRttInfo(&dst.lastRtt, &dst.lastRttVariance)) {
    // Set RTTs to 0 if unavailable
    dst.lastRtt = 0;
    dst.lastRttVariance = 0;
  } else {
    // Our logic to determine if RTT is valid depends on us never
    // getting an RTT of 0. ENet currently ensures RTTs are >= 1.
    assert(dst.lastRtt > 0);
  }

  // Get the current time in milliseconds
  auto now = LiGetMillis();

  // Initialize the measurement start point if this is the first video stat window
  if (!dst.measurementStartTimestamp) {
    dst.measurementStartTimestamp = src.measurementStartTimestamp;
  }

  // Ensure the global measurement timestamp has already started first
  assert(dst.measurementStartTimestamp <= src.measurementStartTimestamp);

  // Compute frames per second metrics for various stages of the video pipeline
  dst.totalFps = (float)dst.totalFrames / ((float)(now - dst.measurementStartTimestamp) / 1000);
  dst.receivedFps = (float)dst.receivedFrames / ((float)(now - dst.measurementStartTimestamp) / 1000);
  dst.decodedFps = (float)dst.decodedFrames / ((float)(now - dst.measurementStartTimestamp) / 1000);
  dst.renderedFps = (float)dst.renderedFrames / ((float)(now - dst.measurementStartTimestamp) / 1000);
}

void MoonlightInstance::FormatVideoStats(VIDEO_STATS& stats, char* output, int length) {
  int ret;
  int offset = 0;
  const char* codecString;

  // Start with an empty string
  output[offset] = 0;

  // Determine the video format being used and assign a readable string
  switch (s_VideoFormat) {
    case VIDEO_FORMAT_H264: // H.264 codec
      codecString = "H.264";
      break;
    case VIDEO_FORMAT_H265: // HEVC codec
      codecString = "HEVC";
      break;
    case VIDEO_FORMAT_H265_MAIN10: // HEVC Main10 codec
      if (LiGetCurrentHostDisplayHdrMode()) {
        codecString = "HEVC 10-bit HDR";
      } else {
        codecString = "HEVC 10-bit SDR";
      }
      break;
    case VIDEO_FORMAT_AV1_MAIN8: // AV1 codec
      codecString = "AV1";
      break;
    case VIDEO_FORMAT_AV1_MAIN10: // AV1 Main10 codec
      if (LiGetCurrentHostDisplayHdrMode()) {
        codecString = "AV1 10-bit HDR";
      } else {
        codecString = "AV1 10-bit SDR";
      }
      break;
    default: // Unknown codec
      assert(false);
      codecString = "UNKNOWN";
      break;
  }

  // If there is a meaningful received frame rate, print basic stream info
  if (stats.receivedFps > 0) {
    if (codecString != nullptr) {
      // Print video resolution, frame rate, and codec name
      ret = snprintf(
        &output[offset], length - offset,
        "Video stream: %dx%d %.2f FPS (Codec: %s)\n",
        s_Width, s_Height, stats.totalFps, codecString
      );
      // Abort if string formatting failed or buffer overflowed
      if (ret < 0 || ret >= length - offset) {
        assert(false);
        return;
      }
      offset += ret;
    }

    // Print frame rates at various stages of the pipeline
    ret = snprintf(
      &output[offset], length - offset,
      "Incoming frame rate from network: %.2f FPS\n"
      "Decoding frame rate: %.2f FPS\n"
      "Rendering frame rate: %.2f FPS\n"
      "Incoming bitrate from network: %.2f Mbps\n",
      stats.receivedFps, stats.decodedFps, stats.renderedFps, stats.receivedBitrate
    );
    // Abort if string formatting failed or buffer overflowed
    if (ret < 0 || ret >= length - offset) {
      assert(false);
      return;
    }
    offset += ret;
  }

  // Only display host processing latency if latency data exists
  if (stats.framesWithHostProcessingLatency > 0) {
    // Print min, max, and average host processing latency in milliseconds
    ret = snprintf(
      &output[offset], length - offset,
      "Host processing latency min/max/average: %.1f/%.1f/%.1f ms\n",
      (float)stats.minHostProcessingLatency / 10, (float)stats.maxHostProcessingLatency / 10,
      (float)stats.totalHostProcessingLatency / 10 / stats.framesWithHostProcessingLatency
    );
    // Abort if string formatting failed or buffer overflowed
    if (ret < 0 || ret >= length - offset) {
      assert(false);
      return;
    }
    offset += ret;
  }

  // Show remaining statistics only if some frames have been rendered
  if (stats.renderedFrames != 0) {
    char rttString[32];
    // Format the round-trip time string
    if (stats.lastRtt != 0) {
      // Print the last RTT including variance in milliseconds
      snprintf(
        rttString, sizeof(rttString),
        "%u ms (variance: %u ms)",
        stats.lastRtt, stats.lastRttVariance
      );
    } else {
      // Otherwise, print as "N/A" if RTT is unavailable
      snprintf(rttString, sizeof(rttString), "N/A");
    }

    // Print detailed drop rates and timing statistics
    ret = snprintf(
      &output[offset], length - offset,
      "Frames dropped by your network connection: %.2f%%\n"
      "Frames dropped due to network jitter: %.2f%%\n"
      "Average network latency: %s\n"
      "Average decoding time: %.2f ms\n"
      "Average frame queue delay: %.2f ms\n"
      "Average rendering time: %.2f ms\n",
      (float)stats.networkDroppedFrames / stats.totalFrames * 100,
      (float)stats.pacerDroppedFrames / stats.decodedFrames * 100,
      rttString,
      (float)stats.totalDecodeTime / stats.decodedFrames,
      (float)stats.totalPacerTime / stats.renderedFrames,
      (float)stats.totalRenderTime / stats.renderedFrames
    );
    // Abort if string formatting failed or buffer overflowed
    if (ret < 0 || ret >= length - offset) {
      assert(false);
      return;
    }
    offset += ret;
  }
}

void MoonlightInstance::TogglePerformanceStats() {
  // Toggle the performance stats overlay flag
  m_PerformanceStatsEnabled = !m_PerformanceStatsEnabled;

  // Notify the JS code that performance stats overlay is enabled or disabled
  if (m_PerformanceStatsEnabled) {
    PostToJs(std::string("StatMsg: ") + s_StatString.data());
  } else {
    PostToJs(std::string("NoStatMsg: "));
  }
}

bool MoonlightInstance::WaitFor(std::condition_variable* variable, const char* waitName, uint32_t timeoutMs, std::function<bool()> condition) {
  std::unique_lock<std::mutex> lock(m_Mutex);
  bool satisfied = variable->wait_for(lock, std::chrono::milliseconds(timeoutMs), condition);
  if (!satisfied) {
    ClLogMessage("Timed out waiting for %s after %u ms: attemptId=%u, lifecycle=%s, emssState=%s, videoStarted=%d, sessionId=%u\n",
      waitName, timeoutMs, m_StreamAttemptId.load(), GetLifecycleName(),
      EmssReadyStateName(m_EmssReadyState), m_VideoStarted.load(),
      static_cast<unsigned int>(m_VideoSessionId.load()));
    return false;
  }

  ClLogMessage("Finished waiting for %s: attemptId=%u, emssState=%s, videoStarted=%d, sessionId=%u\n",
    waitName, m_StreamAttemptId.load(), EmssReadyStateName(m_EmssReadyState),
    m_VideoStarted.load(), static_cast<unsigned int>(m_VideoSessionId.load()));
  return true;
}

bool MoonlightInstance::ProbeVideoTrack(const char* mimeType, int width, int height, int redrawRate) {
  const uint64_t probeStartMs = LiGetMillis();

  if (GetLifecycle() != StreamLifecycle::Idle) {
    ClLogMessage("Video codec probe skipped because lifecycle is %s\n", GetLifecycleName());
    return false;
  }

  if (m_Source) {
    m_MediaElement.SetSrc(nullptr);
    m_VideoTrack = samsung::wasm::ElementaryMediaTrack();
    m_Source.reset();
  }

  {
    std::unique_lock<std::mutex> lock(m_Mutex);
    m_EmssReadyState = EmssReadyState::kDetached;
    m_VideoStarted = false;
    m_VideoSessionId.store(0);
  }

  ClLogMessage("Video codec probe track setup started: mimeType=%s, width=%d, height=%d, fps=%d\n",
    mimeType, width, height, redrawRate);

  auto probeSource = std::make_unique<samsung::wasm::ElementaryMediaStreamSource>(
    samsung::wasm::ElementaryMediaStreamSource::LatencyMode::kLow,
    samsung::wasm::ElementaryMediaStreamSource::RenderingMode::kMediaElement
  );
  probeSource->SetListener(&m_SourceListener);

  m_MediaElement.SetSrc(probeSource.get());
  if (!WaitFor(&m_EmssStateChanged, "codec probe source closed", 750, [this] {
    return m_EmssReadyState == EmssReadyState::kClosed;
  })) {
    m_MediaElement.SetSrc(nullptr);
    ClLogMessage("Video codec probe track setup failed before AddTrack: mimeType=%s, elapsedMs=%llu\n",
      mimeType, (unsigned long long)(LiGetMillis() - probeStartMs));
    return false;
  }

  auto addTrackResult = probeSource->AddTrack(
    samsung::wasm::ElementaryVideoTrackConfig {
      mimeType,
      {},
      samsung::wasm::DecodingMode::kHardware,
      static_cast<uint32_t>(width),
      static_cast<uint32_t>(height),
      static_cast<uint32_t>(redrawRate),
      1,
    }
  );
  const bool supported = static_cast<bool>(addTrackResult);
  ClLogMessage("Video codec probe AddTrack result: mimeType=%s, supported=%d, elapsedMs=%llu\n",
    mimeType, supported, (unsigned long long)(LiGetMillis() - probeStartMs));

  m_MediaElement.SetSrc(nullptr);
  {
    std::unique_lock<std::mutex> lock(m_Mutex);
    m_EmssReadyState = EmssReadyState::kDetached;
    m_VideoStarted = false;
    m_VideoSessionId.store(0);
  }

  return supported;
}

void MoonlightInstance::ProbeVideoCodecSupport(
  int callbackId,
  std::string width,
  std::string height,
  std::string fps,
  bool hdrMode,
  int serverCodecModeSupport,
  std::string preferredCodec,
  std::string disabledMimeTypes) {
  // EMSS source state changes are delivered through the browser main thread.
  // Running the waits from an embind call on that thread prevents OnSourceClosed
  // from being delivered, making every candidate time out and freezing Flutter.
  m_Dispatcher.post_job(std::bind(
    &MoonlightInstance::ProbeVideoCodecSupportPrivate,
    this,
    callbackId,
    std::move(width),
    std::move(height),
    std::move(fps),
    hdrMode,
    serverCodecModeSupport,
    std::move(preferredCodec),
    std::move(disabledMimeTypes)), false);
}

void MoonlightInstance::ProbeVideoCodecSupportPrivate(
  int callbackId,
  std::string width,
  std::string height,
  std::string fps,
  bool hdrMode,
  int serverCodecModeSupport,
  std::string preferredCodec,
  std::string disabledMimeTypes) {
  try {
    PostPromiseMessage(callbackId, "resolve", ProbeVideoCodecSupportSync(
      std::move(width), std::move(height), std::move(fps), hdrMode,
      serverCodecModeSupport, std::move(preferredCodec), std::move(disabledMimeTypes)));
  } catch (const std::exception& error) {
    ClLogMessage("Video codec probe failed with exception: %s\n", error.what());
    PostPromiseMessage(callbackId, "reject", error.what());
  } catch (...) {
    ClLogMessage("Video codec probe failed with unknown exception\n");
    PostPromiseMessage(callbackId, "reject", "Video codec probe failed with an unknown exception.");
  }
}

std::string MoonlightInstance::ProbeVideoCodecSupportSync(
  std::string width,
  std::string height,
  std::string fps,
  bool hdrMode,
  int serverCodecModeSupport,
  std::string preferredCodec,
  std::string disabledMimeTypes) {
  const uint64_t probeStartMs = LiGetMillis();
  int parsedWidth = 0;
  int parsedHeight = 0;
  int parsedFps = 0;

  m_ProbedVideoFormat = 0;
  m_ProbedVideoWidth = 0;
  m_ProbedVideoHeight = 0;
  m_ProbedVideoFps = 0;
  m_ProbedVideoMimeType.clear();
  m_ProbedVideoProfileLabel.clear();

  try {
    parsedWidth = std::stoi(width);
    parsedHeight = std::stoi(height);
    parsedFps = std::stoi(fps);
  } catch (const std::exception& e) {
    std::ostringstream errorJson;
    errorJson << "{\"error\":\"invalid dimensions\",\"message\":";
    AppendJsonString(errorJson, e.what());
    errorJson << "}";
    return errorJson.str();
  }

  const int disabledMimeTypeCount = CountDisabledMimeTypes(disabledMimeTypes);
  ClLogMessage("Video codec probe started: preferredCodec=%s, hdrMode=%d, width=%d, height=%d, fps=%d, serverCodecModeSupport=0x%x, disabledMimeTypes=%d\n",
    preferredCodec.c_str(), hdrMode, parsedWidth, parsedHeight, parsedFps, serverCodecModeSupport, disabledMimeTypeCount);

  std::vector<VideoFormatCandidate> formats = BuildVideoFormatProbeOrder(preferredCodec, hdrMode, serverCodecModeSupport);
  ClLogMessage("Video codec probe format queue prepared: candidateFormats=%u\n",
    static_cast<unsigned int>(formats.size()));

  std::ostringstream candidatesJson;
  bool wroteCandidate = false;
  bool selected = false;
  VideoFormatCandidate selectedFormat = {};
  VideoProfileSelection selectedProfile = {};
  int attemptedProfiles = 0;
  int skippedProfiles = 0;
  int formatIndex = 0;
  auto appendCandidateJson = [&](const VideoFormatCandidate& format, const VideoProfileSelection& profile, int currentFormatIndex, int currentProfileIndex, bool supported, bool skipped, const char* skipReason) {
    if (wroteCandidate) {
      candidatesJson << ",";
    }
    candidatesJson << "{";
    candidatesJson << "\"codec\":";
    AppendJsonString(candidatesJson, format.codec);
    candidatesJson << ",\"hdr\":" << (format.hdr ? "true" : "false");
    candidatesJson << ",\"videoFormat\":" << format.videoFormat;
    candidatesJson << ",\"formatIndex\":" << currentFormatIndex;
    candidatesJson << ",\"profileIndex\":" << currentProfileIndex;
    candidatesJson << ",\"profile\":";
    AppendJsonString(candidatesJson, profile.label);
    candidatesJson << ",\"mimeType\":";
    AppendJsonString(candidatesJson, profile.mimeType);
    candidatesJson << ",\"supported\":" << (supported ? "true" : "false");
    candidatesJson << ",\"skipped\":" << (skipped ? "true" : "false");
    candidatesJson << ",\"skipReason\":";
    AppendJsonString(candidatesJson, skipReason ? skipReason : "");
    candidatesJson << "}";
    wroteCandidate = true;
  };

  for (const VideoFormatCandidate& format : formats) {
    std::vector<VideoProfileSelection> profiles = GetVideoProfileCandidates(format.videoFormat, parsedWidth, parsedHeight, parsedFps);
    ClLogMessage("Video codec probe format started: index=%d, codec=%s, hdr=%d, format=0x%x, profileCandidates=%u\n",
      formatIndex, format.codec, format.hdr, format.videoFormat, static_cast<unsigned int>(profiles.size()));

    int profileIndex = 0;
    for (const VideoProfileSelection& profile : profiles) {
      if (IsMimeTypeDisabled(disabledMimeTypes, profile.mimeType)) {
        skippedProfiles++;
        ClLogMessage("Video codec probe candidate skipped: formatIndex=%d, profileIndex=%d, codec=%s, hdr=%d, format=0x%x, profile=%s, mimeType=%s, reason=disabled by user\n",
          formatIndex, profileIndex, format.codec, format.hdr, format.videoFormat, profile.label, profile.mimeType);
        appendCandidateJson(format, profile, formatIndex, profileIndex, false, true, "disabledByUser");
        profileIndex++;
        continue;
      }

      attemptedProfiles++;
      const bool supported = ProbeVideoTrack(profile.mimeType, parsedWidth, parsedHeight, parsedFps);
      ClLogMessage("Video codec probe candidate result: formatIndex=%d, profileIndex=%d, codec=%s, hdr=%d, format=0x%x, profile=%s, mimeType=%s, supported=%d\n",
        formatIndex, profileIndex, format.codec, format.hdr, format.videoFormat, profile.label, profile.mimeType, supported);

      appendCandidateJson(format, profile, formatIndex, profileIndex, supported, false, "");

      if (supported) {
        selected = true;
        selectedFormat = format;
        selectedProfile = profile;
        break;
      }

      profileIndex++;
    }

    if (selected) {
      break;
    }

    formatIndex++;
  }

  if (selected) {
    m_ProbedVideoFormat = selectedFormat.videoFormat;
    m_ProbedVideoWidth = parsedWidth;
    m_ProbedVideoHeight = parsedHeight;
    m_ProbedVideoFps = parsedFps;
    m_ProbedVideoMimeType = selectedProfile.mimeType;
    m_ProbedVideoProfileLabel = selectedProfile.label;

    ClLogMessage("Video codec probe selected: codec=%s, hdr=%d, format=0x%x, profile=%s, mimeType=%s\n",
      selectedFormat.codec, selectedFormat.hdr, selectedFormat.videoFormat, selectedProfile.label, selectedProfile.mimeType);
  } else {
    ClLogMessage("Video codec probe found no supported candidates\n");
  }

  ClLogMessage("Video codec probe complete: selected=%s, attemptedProfiles=%d, skippedProfiles=%d, disabledMimeTypes=%d, elapsedMs=%llu\n",
    BoolText(selected), attemptedProfiles, skippedProfiles, disabledMimeTypeCount, (unsigned long long)(LiGetMillis() - probeStartMs));

  std::ostringstream resultJson;
  resultJson << "{";
  resultJson << "\"requestedCodec\":";
  AppendJsonString(resultJson, preferredCodec);
  resultJson << ",\"requestedHdrMode\":" << (hdrMode ? "true" : "false");
  resultJson << ",\"width\":" << parsedWidth;
  resultJson << ",\"height\":" << parsedHeight;
  resultJson << ",\"fps\":" << parsedFps;
  resultJson << ",\"selectedCodec\":";
  AppendJsonString(resultJson, selected ? selectedFormat.codec : "");
  resultJson << ",\"selectedHdrMode\":" << (selected && selectedFormat.hdr ? "true" : "false");
  resultJson << ",\"selectedVideoFormat\":" << (selected ? selectedFormat.videoFormat : 0);
  resultJson << ",\"selectedProfile\":";
  AppendJsonString(resultJson, selected ? selectedProfile.label : "");
  resultJson << ",\"selectedMimeType\":";
  AppendJsonString(resultJson, selected ? selectedProfile.mimeType : "");
  resultJson << ",\"attemptedProfiles\":" << attemptedProfiles;
  resultJson << ",\"skippedProfiles\":" << skippedProfiles;
  resultJson << ",\"disabledMimeTypes\":" << disabledMimeTypeCount;
  resultJson << ",\"elapsedMs\":" << (LiGetMillis() - probeStartMs);
  resultJson << ",\"fallback\":" << (selected && (preferredCodec != selectedFormat.codec || hdrMode != selectedFormat.hdr) ? "true" : "false");
  resultJson << ",\"candidates\":[" << candidatesJson.str() << "]";
  resultJson << "}";

  return resultJson.str();
}

DECODER_RENDERER_CALLBACKS MoonlightInstance::s_DrCallbacks = {
  .setup = MoonlightInstance::VidDecSetup,
  .cleanup = MoonlightInstance::VidDecCleanup,
  .submitDecodeUnit = MoonlightInstance::VidDecSubmitDecodeUnit,
  .capabilities = CAPABILITY_SLICES_PER_FRAME(4),
};
