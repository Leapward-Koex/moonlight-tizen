#include "moonlight_wasm.hpp"

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <pairing.h>
#include <exception>
#include <iostream>

extern char* g_UniqueId;

#include <emscripten.h>
#include <emscripten/html5.h>

#include <openssl/evp.h>
#include <openssl/rand.h>

#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>

// Requests the Wasm module to connect to the specified server
#define MSG_START_REQUEST "startRequest"
// Requests the Wasm module to stop streaming
#define MSG_STOP_REQUEST "stopRequest"
// Sent by the Wasm module when streaming has stopped, whether requested by the user or not
#define MSG_STREAM_TERMINATED "streamTerminated: "
// Sent by the Wasm module as the native stream lifecycle changes
#define MSG_STREAM_STARTING "streamStarting: "
#define MSG_STREAM_STARTED "streamStarted: "
#define MSG_STREAM_START_FAILED "streamStartFailed: "
#define MSG_STREAM_STOPPING "streamStopping: "
// Requests the Wasm module to open the specified URL
#define MSG_OPENURL "openUrl"

#define ML_ERROR_WASM_START_FAILED -200
#define ML_ERROR_WASM_STOP_FAILED -201

using EmssLatencyMode = samsung::wasm::ElementaryMediaStreamSource::LatencyMode;
using EmssRenderingMode = samsung::wasm::ElementaryMediaStreamSource::RenderingMode;

MoonlightInstance* g_Instance;

extern "C" {
int g_AudioPacketDurationOverride = 0;
int g_AudioJitterMsOverride = 0;
}

MoonlightInstance::MoonlightInstance()
  : m_OpusDecoder(NULL),
    m_MouseLocked(false),
    m_MouseLastPosX(-1),
    m_MouseLastPosY(-1),
    m_WaitingForAllModifiersUp(false),
    m_AccumulatedTicks(0),
    m_MouseDeltaX(0),
    m_MouseDeltaY(0),
    m_HttpThreadPoolSequence(0),
    m_Dispatcher("Curl"),
    m_Running(false),
    m_StreamLifecycle(StreamLifecycle::Idle),
    m_StreamAttemptId(0),
    m_ConnectionThread(),
    m_InputThread(),
    m_StopThread(),
    m_ConnectionThreadCreated(false),
    m_InputThreadCreated(false),
    m_StopThreadCreated(false),
    m_Mutex(),
    m_EmssStateChanged(),
    m_EmssVideoStateChanged(),
    m_EmssReadyState(EmssReadyState::kDetached),
    m_VideoStarted(false),
    m_VideoSessionId(0),
    m_MediaElement("wasm_module"),
    m_Source(nullptr),
    m_SourceListener(this),
    m_VideoTrackListener(this),
    m_VideoTrack() {
      m_Dispatcher.start();
      ClLogMessage("MoonlightInstance initialized\n");
    }

MoonlightInstance::~MoonlightInstance() { 
  ClLogMessage("MoonlightInstance shutting down\n");
  m_Dispatcher.stop();
}

const char* MoonlightInstance::StreamLifecycleName(StreamLifecycle lifecycle) {
  switch (lifecycle) {
    case StreamLifecycle::Idle:
      return "Idle";
    case StreamLifecycle::Starting:
      return "Starting";
    case StreamLifecycle::Connected:
      return "Connected";
    case StreamLifecycle::Stopping:
      return "Stopping";
    default:
      return "Unknown";
  }
}

const char* MoonlightInstance::EmssReadyStateName(EmssReadyState state) {
  switch (state) {
    case EmssReadyState::kDetached:
      return "Detached";
    case EmssReadyState::kClosed:
      return "Closed";
    case EmssReadyState::kOpenPending:
      return "OpenPending";
    case EmssReadyState::kOpen:
      return "Open";
    default:
      return "Unknown";
  }
}

StreamLifecycle MoonlightInstance::GetLifecycle() const {
  return m_StreamLifecycle.load();
}

const char* MoonlightInstance::GetLifecycleName() const {
  return StreamLifecycleName(GetLifecycle());
}

uint32_t MoonlightInstance::GetStreamAttemptId() const {
  return m_StreamAttemptId.load();
}

bool MoonlightInstance::TrySetLifecycle(StreamLifecycle expected, StreamLifecycle desired, const char* reason) {
  StreamLifecycle original = expected;
  bool changed = m_StreamLifecycle.compare_exchange_strong(expected, desired);
  ClLogMessage("Stream lifecycle %s: %s -> %s, expected=%s, actual=%s, changed=%d, attemptId=%u\n",
    reason, StreamLifecycleName(original), StreamLifecycleName(desired),
    StreamLifecycleName(original), StreamLifecycleName(expected), changed,
    m_StreamAttemptId.load());
  return changed;
}

void MoonlightInstance::SetLifecycle(StreamLifecycle lifecycle, const char* reason) {
  StreamLifecycle previous = m_StreamLifecycle.exchange(lifecycle);
  ClLogMessage("Stream lifecycle %s: %s -> %s, attemptId=%u\n",
    reason, StreamLifecycleName(previous), StreamLifecycleName(lifecycle),
    m_StreamAttemptId.load());
}

void MoonlightInstance::JoinStaleThreadsIfIdle() {
  if (GetLifecycle() != StreamLifecycle::Idle) {
    return;
  }

  if (m_InputThreadCreated.exchange(false)) {
    ClLogMessage("Joining stale input thread before new start: attemptId=%u\n", m_StreamAttemptId.load());
    m_Running.store(false);
    pthread_join(m_InputThread, NULL);
    ClLogMessage("Joined stale input thread before new start\n");
  }

  if (m_ConnectionThreadCreated.exchange(false)) {
    ClLogMessage("Joining stale connection thread before new start: attemptId=%u\n", m_StreamAttemptId.load());
    pthread_join(m_ConnectionThread, NULL);
    ClLogMessage("Joined stale connection thread before new start\n");
  }
}

void MoonlightInstance::ResetMediaStateForStart(uint32_t attemptId) {
  ClLogMessage("Resetting media state for stream start: attemptId=%u, sourceExisting=%d, emssState=%s, videoStarted=%d, sessionId=%u\n",
    attemptId, m_Source ? 1 : 0, EmssReadyStateName(m_EmssReadyState),
    m_VideoStarted.load(), static_cast<unsigned int>(m_VideoSessionId.load()));

  {
    std::unique_lock<std::mutex> lock(m_Mutex);
    m_EmssReadyState = EmssReadyState::kDetached;
    m_VideoStarted = false;
    m_VideoSessionId.store(0);
  }

  if (m_Source) {
    m_MediaElement.SetSrc(nullptr);
  }
  m_VideoTrack = samsung::wasm::ElementaryMediaTrack();
  m_Source.reset();
}

void MoonlightInstance::CompleteStartFailure(uint32_t attemptId, int errorCode, const std::string& reason) {
  StreamLifecycle lifecycle = GetLifecycle();
  ClLogMessage("Completing stream start failure: attemptId=%u, currentAttemptId=%u, lifecycle=%s, error=%d, reason=%s\n",
    attemptId, m_StreamAttemptId.load(), StreamLifecycleName(lifecycle), errorCode, reason.c_str());

  m_Running.store(false);
  UnlockMouse();

  if (lifecycle == StreamLifecycle::Stopping) {
    ClLogMessage("Suppressing streamStartFailed because stop is already in progress: attemptId=%u\n", attemptId);
    return;
  }

  SetLifecycle(StreamLifecycle::Idle, "start failed");
  PostToJs(std::string(MSG_STREAM_START_FAILED) + std::to_string(attemptId) + ":" + std::to_string(errorCode) + ":" + reason);
}

void MoonlightInstance::CompleteStop(uint32_t attemptId, int errorCode, uint64_t stopStartMs) {
  m_Running.store(false);
  UnlockMouse();
  SetLifecycle(StreamLifecycle::Idle, "stop complete");
  m_StopThreadCreated = false;
  ClLogMessage("Stop complete: attemptId=%u, error=%d, elapsedMs=%llu\n",
    attemptId, errorCode, (unsigned long long)(LiGetMillis() - stopStartMs));
  PostToJs(std::string(MSG_STREAM_TERMINATED) + std::to_string(attemptId) + ":" + std::to_string(errorCode));
}

void MoonlightInstance::OnConnectionStarted(uint32_t unused) {
  ClLogMessage("OnConnectionStarted: attemptId=%u, lifecycle=%s, running=%d, videoStarted=%d, source=%d\n",
    m_StreamAttemptId.load(), GetLifecycleName(), m_Running.load(), m_VideoStarted.load(), m_Source ? 1 : 0);

  // Keep the legacy notification for compatibility. The authoritative start
  // completion event is streamStarted, posted after LiStartConnection returns.
  PostToJs(std::string("Connection Established"));
}

void MoonlightInstance::OnConnectionStopped(uint32_t error) {
  uint32_t attemptId = m_StreamAttemptId.load();
  ClLogMessage("OnConnectionStopped: attemptId=%u, error=%u, lifecycle=%s, runningBefore=%d, videoStarted=%d, source=%d\n",
    attemptId, error, GetLifecycleName(), m_Running.load(), m_VideoStarted.load(), m_Source ? 1 : 0);

  // Not running anymore
  m_Running.store(false);

  // Unlock the mouse
  UnlockMouse();

  SetLifecycle(StreamLifecycle::Idle, "connection stopped");

  // Notify the JS code that the stream has ended
  PostToJs(std::string(MSG_STREAM_TERMINATED) + std::to_string(attemptId) + ":" + std::to_string((int)error));
}

MessageResult MoonlightInstance::StopConnection() {
  pthread_t t;
  StreamLifecycle previousLifecycle = GetLifecycle();

  ClLogMessage("StopConnection requested: attemptId=%u, lifecycle=%s, running=%d, videoStarted=%d, source=%d\n",
    m_StreamAttemptId.load(), StreamLifecycleName(previousLifecycle),
    m_Running.load(), m_VideoStarted.load(), m_Source ? 1 : 0);

  if (previousLifecycle == StreamLifecycle::Idle) {
    ClLogMessage("StopConnection ignored because stream lifecycle is already Idle\n");
    return MessageResult::Resolve();
  }

  if (previousLifecycle == StreamLifecycle::Stopping) {
    ClLogMessage("StopConnection ignored because stop is already in progress\n");
    return MessageResult::Resolve();
  }

  if (!TrySetLifecycle(previousLifecycle, StreamLifecycle::Stopping, "stop requested")) {
    return MessageResult::Reject(emscripten::val(std::string("stream lifecycle changed before stop could begin")));
  }

  PostToJs(std::string(MSG_STREAM_STOPPING) + std::to_string(m_StreamAttemptId.load()));

  // Interrupt a pending start before the stop thread waits for it to return.
  LiInterruptConnection();

  // Stopping needs to happen in a separate thread to avoid a potential deadlock
  // caused by us getting a callback to the main thread while inside
  // LiStopConnection.
  int err = pthread_create(&t, NULL, MoonlightInstance::StopThreadFunc, NULL);
  if (err != 0) {
    ClLogMessage("Failed to create stop thread: %d\n", err);
    SetLifecycle(previousLifecycle, "stop thread creation failed");
    return MessageResult::Reject(emscripten::val(err));
  } else {
    m_StopThread = t;
    m_StopThreadCreated = true;
    int detachErr = pthread_detach(t);
    if (detachErr != 0) {
      ClLogMessage("Failed to detach stop thread: attemptId=%u, error=%d\n", m_StreamAttemptId.load(), detachErr);
    }
    ClLogMessage("Stop thread created: attemptId=%u\n", m_StreamAttemptId.load());
  }

  return MessageResult::Resolve();
}

void* MoonlightInstance::StopThreadFunc(void* context) {
  uint64_t stopStartMs = LiGetMillis();
  uint32_t attemptId = g_Instance->m_StreamAttemptId.load();
  ClLogMessage("Stop thread started: attemptId=%u, connectionThreadCreated=%d, inputThreadCreated=%d\n",
    attemptId, g_Instance->m_ConnectionThreadCreated.load(), g_Instance->m_InputThreadCreated.load());

  // We must join the connection thread first, because LiStopConnection must
  // not be invoked during LiStartConnection.
  if (g_Instance->m_ConnectionThreadCreated.exchange(false)) {
    ClLogMessage("Stop thread joining connection thread\n");
    pthread_join(g_Instance->m_ConnectionThread, NULL);
    ClLogMessage("Stop thread joined connection thread after %llu ms\n",
      (unsigned long long)(LiGetMillis() - stopStartMs));
  } else {
    ClLogMessage("Stop thread skipped connection join because no connection thread was created\n");
  }

  // Force raise all modifier keys to avoid leaving them down after disconnecting
  LiSendKeyboardEvent(0xA0, KEY_ACTION_UP, 0);
  LiSendKeyboardEvent(0xA1, KEY_ACTION_UP, 0);
  LiSendKeyboardEvent(0xA2, KEY_ACTION_UP, 0);
  LiSendKeyboardEvent(0xA3, KEY_ACTION_UP, 0);
  LiSendKeyboardEvent(0xA4, KEY_ACTION_UP, 0);
  LiSendKeyboardEvent(0xA5, KEY_ACTION_UP, 0);

  // Not running anymore
  g_Instance->m_Running.store(false);

  // We also need to stop this thread after the connection thread, because it
  // depends on being initialized there.
  if (g_Instance->m_InputThreadCreated.exchange(false)) {
    ClLogMessage("Stop thread joining input thread\n");
    pthread_join(g_Instance->m_InputThread, NULL);
    ClLogMessage("Stop thread joined input thread\n");
  } else {
    ClLogMessage("Stop thread skipped input join because no input thread was created\n");
  }

  // Stop the connection
  ClLogMessage("Stop thread calling LiStopConnection\n");
  LiStopConnection();
  g_Instance->CompleteStop(attemptId, 0, stopStartMs);
  return NULL;
}

void* MoonlightInstance::InputThreadFunc(void* context) {
  MoonlightInstance* me = (MoonlightInstance*)context;

  while (me->m_Running.load()) {
    me->PollGamepads();
    me->ReportMouseMovement();

    // Poll every 5 ms
    usleep(5 * 1000);
  }

  return NULL;
}

void* MoonlightInstance::ConnectionThreadFunc(void* context) {
  MoonlightInstance* me = (MoonlightInstance*)context;
  int err;
  SERVER_INFORMATION serverInfo;
  uint64_t connectStartMs = LiGetMillis();
  uint32_t attemptId = me->m_StreamAttemptId.load();

  ClLogMessage("Connection thread started: attemptId=%u, host=%s:%d, appVersion=%s, gfeVersion=%s, videoFormats=0x%x, audioConfig=0x%x, packetSize=%d, audioPacketDurationSetting=%d, audioJitterSetting=%d, playHostAudio=%d\n",
    attemptId, me->m_Host.c_str(), me->m_HttpPort, me->m_AppVersion.c_str(), me->m_GfeVersion.c_str(),
    me->m_StreamConfig.supportedVideoFormats, me->m_StreamConfig.audioConfiguration,
    me->m_StreamConfig.packetSize, me->m_AudioPacketDuration, me->m_AudioJitterMs,
    me->m_PlayHostAudioEnabled);

  // Post a status update before we begin
  PostToJs(std::string("Starting connection to ") + me->m_Host);

  // Populate the server information
  LiInitializeServerInformation(&serverInfo);
  serverInfo.address = me->m_Host.c_str();
  serverInfo.serverInfoAppVersion = me->m_AppVersion.c_str();
  serverInfo.serverInfoGfeVersion = me->m_GfeVersion.c_str();
  serverInfo.rtspSessionUrl = me->m_RtspUrl.c_str();

  // Initialize the server codec mode support with default value
  serverInfo.serverCodecModeSupport = 0;
  // Handle setting of server codec mode support values ​​based on the selected video format
  if (me->m_StreamConfig.supportedVideoFormats & VIDEO_FORMAT_H264) { // H.264
    // Apply the appropriate value for the H.264 server codec
    serverInfo.serverCodecModeSupport |= SCM_H264;
    PostToJs("Selecting the server code mode to: SCM_H264");
  }
  if (me->m_StreamConfig.supportedVideoFormats & VIDEO_FORMAT_H265) { // HEVC
    // Apply the appropriate value for the HEVC server codec
    serverInfo.serverCodecModeSupport |= SCM_HEVC;
    PostToJs("Selecting the server code mode to: SCM_HEVC");
  }
  if (me->m_StreamConfig.supportedVideoFormats & VIDEO_FORMAT_H265_MAIN10) { // HEVC Main10
    // Apply the appropriate value for the HEVC Main10 server codec
    serverInfo.serverCodecModeSupport |= SCM_HEVC_MAIN10;
    PostToJs("Selecting the server code mode to: SCM_HEVC_MAIN10");
  }
  if (me->m_StreamConfig.supportedVideoFormats & VIDEO_FORMAT_AV1_MAIN8) { // AV1
    // Apply the appropriate value for the AV1 server codec
    serverInfo.serverCodecModeSupport |= SCM_AV1_MAIN8;
    PostToJs("Selecting the server code mode to: SCM_AV1_MAIN8");
  }
  if (me->m_StreamConfig.supportedVideoFormats & VIDEO_FORMAT_AV1_MAIN10) { // AV1 Main10
    // Apply the appropriate value for the AV1 Main10 server codec
    serverInfo.serverCodecModeSupport |= SCM_AV1_MAIN10;
    PostToJs("Selecting the server code mode to: SCM_AV1_MAIN10");
  }
  // Handle fall back logic for server codec mode support
  if (serverInfo.serverCodecModeSupport == 0) { // Unset
    // Fallback to H.264 if no server codec was selected
    serverInfo.serverCodecModeSupport = SCM_H264;
    PostToJs("Selecting the fallback server code mode to: SCM_H264");
  }

  // Apply user-selected audio packet duration override. Auto maps to 10 ms
  // because it is a stable low-latency default on Tizen's Web Audio path.
  g_AudioPacketDurationOverride = me->m_AudioPacketDuration != 0 ? me->m_AudioPacketDuration : 10;

  // Apply user-selected Web Audio jitter target. Zero means the scheduler uses
  // its default of 100 ms.
  g_AudioJitterMsOverride = me->m_AudioJitterMs;
  ClLogMessage("Audio startup overrides applied: packetDurationMs=%d, jitterTargetMs=%d\n",
    g_AudioPacketDurationOverride, g_AudioJitterMsOverride != 0 ? g_AudioJitterMsOverride : 100);

  err = LiStartConnection(&serverInfo, &me->m_StreamConfig, &MoonlightInstance::s_ClCallbacks,
    &MoonlightInstance::s_DrCallbacks, &MoonlightInstance::s_ArCallbacks, NULL, 0, NULL, 0);
  if (err != 0) {
    ClLogMessage("LiStartConnection failed after %llu ms: attemptId=%u, err=%d, lifecycle=%s\n",
      (unsigned long long)(LiGetMillis() - connectStartMs), attemptId, err, me->GetLifecycleName());

    if (me->GetLifecycle() != StreamLifecycle::Stopping) {
      me->CompleteStartFailure(attemptId, ML_ERROR_WASM_START_FAILED, std::string("LiStartConnection failed with err=") + std::to_string(err));
    }
    return NULL;
  }

  if (!me->TrySetLifecycle(StreamLifecycle::Starting, StreamLifecycle::Connected, "connection established")) {
    ClLogMessage("LiStartConnection returned but lifecycle is no longer Starting; suppressing streamStarted: attemptId=%u, lifecycle=%s\n",
      attemptId, me->GetLifecycleName());
    return NULL;
  }

  // Set running state before starting connection-specific threads
  me->m_Running.store(true);

  int inputThreadErr = pthread_create(&me->m_InputThread, NULL, MoonlightInstance::InputThreadFunc, me);
  if (inputThreadErr != 0) {
    ClLogMessage("Failed to create input polling thread: attemptId=%u, error=%d\n", attemptId, inputThreadErr);
  } else {
    me->m_InputThreadCreated = true;
    ClLogMessage("Connection established after %llu ms; input polling thread started, attemptId=%u\n",
      (unsigned long long)(LiGetMillis() - connectStartMs), attemptId);
  }

  if (me->GetLifecycle() != StreamLifecycle::Connected) {
    ClLogMessage("Connection established but stop began before streamStarted notification; suppressing streamStarted: attemptId=%u, lifecycle=%s\n",
      attemptId, me->GetLifecycleName());
    return NULL;
  }

  PostToJs(std::string(MSG_STREAM_STARTED) + std::to_string(attemptId));
  return NULL;
}

static void HexStringToBytes(const char* str, char* output) {
  for (size_t i = 0; i < strlen(str); i += 2) {
    sscanf(&str[i], "%2hhx", &output[i / 2]);
  }
}

MessageResult MoonlightInstance::StartStream(std::string host, int httpPort, std::string width, std::string height, std::string fps, std::string bitrate,
  std::string rikey, std::string rikeyid, std::string appversion, std::string gfeversion, std::string rtspurl, int serverCodecModeSupport,
  bool framePacing, bool optimizeGames, bool rumbleFeedback, bool mouseEmulation, bool flipABfaceButtons, bool flipXYfaceButtons,
  std::string audioConfig, int audioPacketDuration, int audioJitterMs, bool playHostAudio, std::string videoCodec, bool hdrMode, bool fullRange, bool gameMode,
  bool disableWarnings, bool performanceStats) {
  JoinStaleThreadsIfIdle();

  StreamLifecycle lifecycle = GetLifecycle();
  if (lifecycle != StreamLifecycle::Idle) {
    std::string reason = std::string("stream lifecycle is ") + StreamLifecycleName(lifecycle);
    ClLogMessage("StartStream rejected: %s, currentAttemptId=%u\n", reason.c_str(), m_StreamAttemptId.load());
    return MessageResult::Reject(emscripten::val(reason));
  }

  uint32_t attemptId = m_StreamAttemptId.fetch_add(1) + 1;
  SetLifecycle(StreamLifecycle::Starting, "start requested");
  m_Running.store(false);
  m_ConnectionThreadCreated = false;
  m_InputThreadCreated = false;
  m_StopThreadCreated = false;

  ClLogMessage("StartStream requested: attemptId=%u, host=%s:%d, mode=%sx%s@%s, bitrate=%s Kbps, codec=%s, audio=%s, audioPacketDuration=%d, audioJitterMs=%d, playHostAudio=%d, gameMode=%d, runningBefore=%d, videoStarted=%d, sourceExisting=%d\n",
    attemptId,
    host.c_str(), httpPort, width.c_str(), height.c_str(), fps.c_str(), bitrate.c_str(),
    videoCodec.c_str(), audioConfig.c_str(), audioPacketDuration, audioJitterMs, playHostAudio,
    gameMode, m_Running.load(), m_VideoStarted.load(), m_Source ? 1 : 0);

  auto failStartSetup = [&](const std::string& reason) {
    ClLogMessage("StartStream setup failed before connection thread: attemptId=%u, reason=%s\n",
      attemptId, reason.c_str());
    CompleteStartFailure(attemptId, ML_ERROR_WASM_START_FAILED, reason);
    return MessageResult::Reject(emscripten::val(reason));
  };

  try {
  PostToJs(std::string(MSG_STREAM_STARTING) + std::to_string(attemptId));
  ResetMediaStateForStart(attemptId);

  PostToJs("Setting the Host address to: " + host + ":" + std::to_string(httpPort));
  PostToJs("Setting the Video resolution to: " + width + "x" + height);
  PostToJs("Setting the Video frame rate to: " + fps + " FPS");
  PostToJs("Setting the Video bitrate to: " + bitrate + " Kbps");
  PostToJs("Setting the Remote input key to: " + rikey);
  PostToJs("Setting the Remote input key ID to: " + rikeyid);
  PostToJs("Setting the App version to: " + appversion);
  PostToJs("Setting the GFE version to: " + gfeversion);
  PostToJs("Setting the RTSP session URL to: " + rtspurl);
  PostToJs("Setting the Server codec mode support to: " + std::to_string(serverCodecModeSupport));
  PostToJs("Setting the Video frame pacing to: " + std::to_string(framePacing));
  PostToJs("Setting the Optimize game settings to: " + std::to_string(optimizeGames));
  PostToJs("Setting the Rumble feedback to: " + std::to_string(rumbleFeedback));
  PostToJs("Setting the Mouse emulation to: " + std::to_string(mouseEmulation));
  PostToJs("Setting the Flip A/B face buttons to: " + std::to_string(flipABfaceButtons));
  PostToJs("Setting the Flip X/Y face buttons to: " + std::to_string(flipXYfaceButtons));
  PostToJs("Setting the Audio configuration to: " + audioConfig);
  PostToJs("Setting the Audio packet duration to: " + (audioPacketDuration ? std::to_string(audioPacketDuration) + " ms" : "auto"));
  PostToJs("Setting the Audio jitter buffer to: " + (audioJitterMs ? std::to_string(audioJitterMs) + " ms" : "auto (100 ms)"));
  PostToJs("Setting the Play host audio to: " + std::to_string(playHostAudio));
  PostToJs("Setting the Video codec to: " + videoCodec);
  PostToJs("Setting the Video HDR mode to: " + std::to_string(hdrMode));
  PostToJs("Setting the Full color range to: " + std::to_string(fullRange));
  PostToJs("Setting the Game mode to: " + std::to_string(gameMode));
  PostToJs("Setting the Disable connection warnings to: " + std::to_string(disableWarnings));
  PostToJs("Setting the Performance statistics to: " + std::to_string(performanceStats));

  // Populate the stream configuration
  LiInitializeStreamConfiguration(&m_StreamConfig);
  m_StreamConfig.width = stoi(width);
  m_StreamConfig.height = stoi(height);
  m_StreamConfig.fps = stoi(fps);
  m_StreamConfig.bitrate = stoi(bitrate); // kilobits per second
  m_StreamConfig.packetSize = 1392;
  m_StreamConfig.streamingRemotely = STREAM_CFG_AUTO;

  // Initialize the audio configuration with default value
  m_StreamConfig.audioConfiguration = 0;
  // Handle setting of audio configuration values ​​based on the selected audio
  if (audioConfig == "Stereo") { // Stereo
    // Apply the appropriate value for the Stereo audio
    m_StreamConfig.audioConfiguration |= AUDIO_CONFIGURATION_STEREO;
    PostToJs("Selecting the audio config to: AUDIO_CONFIGURATION_STEREO");
  } else if (audioConfig == "51Surround") { // 5.1 Surround
    // Apply the appropriate value for the 5.1 Surround audio
    m_StreamConfig.audioConfiguration |= AUDIO_CONFIGURATION_51_SURROUND;
    PostToJs("Selecting the audio config to: AUDIO_CONFIGURATION_51_SURROUND");
  } else if (audioConfig == "71Surround") { // 7.1 Surround
    // Apply the appropriate value for the 7.1 Surround audio
    m_StreamConfig.audioConfiguration |= AUDIO_CONFIGURATION_71_SURROUND;
    PostToJs("Selecting the audio config to: AUDIO_CONFIGURATION_71_SURROUND");
  } else { // Unknown
    // Default case for unsupported audio selection
    ClLogMessage("Unsupported audio config '%s' detected! Reverting to the default audio...\n", audioConfig.c_str());
  }
  // Handle fall back logic for audio configuration
  if (m_StreamConfig.audioConfiguration == 0) { // Unset
    // Fallback to Stereo if no audio was selected
    m_StreamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    PostToJs("Selecting the fallback audio config to: AUDIO_CONFIGURATION_STEREO");
  }
  // Store the audio configuration value from the stream configurations
  m_AudioConfig = m_StreamConfig.audioConfiguration;

  // Initialize the supported video format with default value
  m_StreamConfig.supportedVideoFormats = 0;
  // Handle setting of supported video format values ​​based on the selected codec
  if (videoCodec == "H264") { // H.264
    // Apply the appropriate value for the H.264 codec
    m_StreamConfig.supportedVideoFormats |= VIDEO_FORMAT_H264;
    PostToJs("Selecting the video format to: VIDEO_FORMAT_H264");
  } else if (videoCodec == "HEVC") { // HEVC
    // Apply the desired HDR or SDR profile ​for the HEVC codec based on the HDR toggle switch state
    m_StreamConfig.supportedVideoFormats |= hdrMode ? VIDEO_FORMAT_H265_MAIN10 : VIDEO_FORMAT_H265;
    PostToJs(hdrMode ? "Selecting the video format to: VIDEO_FORMAT_H265_MAIN10" : "Selecting the video format to: VIDEO_FORMAT_H265");
  } else if (videoCodec == "AV1") { // AV1
    // Apply the desired HDR or SDR profile ​for the AV1 codec based on the HDR toggle switch state
    m_StreamConfig.supportedVideoFormats |= hdrMode ? VIDEO_FORMAT_AV1_MAIN10 : VIDEO_FORMAT_AV1_MAIN8;
    PostToJs(hdrMode ? "Selecting the video format to: VIDEO_FORMAT_AV1_MAIN10" : "Selecting the video format to: VIDEO_FORMAT_AV1_MAIN8");
  } else { // Unknown
    // Default case for unsupported codec selection
    ClLogMessage("Unsupported video codec '%s' detected! Reverting to the default codec...\n", videoCodec.c_str());
  }
  // Handle fall back logic for supported video formats
  if (m_StreamConfig.supportedVideoFormats == 0) { // Unset
    // Fallback to H.264 if no codec was selected
    m_StreamConfig.supportedVideoFormats = VIDEO_FORMAT_H264;
    PostToJs("Selecting the fallback video format to: VIDEO_FORMAT_H264");
  }
  ClLogMessage("Stream configuration prepared: width=%d, height=%d, fps=%d, bitrate=%d, packetSize=%d, supportedVideoFormats=0x%x, audioConfiguration=0x%x, remoteStreaming=%d\n",
    m_StreamConfig.width, m_StreamConfig.height, m_StreamConfig.fps, m_StreamConfig.bitrate,
    m_StreamConfig.packetSize, m_StreamConfig.supportedVideoFormats,
    m_StreamConfig.audioConfiguration, m_StreamConfig.streamingRemotely);

  // Initialize the color range with default value
  m_StreamConfig.colorRange = 0;
  // Apply the desired color range ​based on the toggle switch state
  m_StreamConfig.colorRange |= fullRange ? COLOR_RANGE_FULL : COLOR_RANGE_LIMITED;

  // Limit encryption to devices that do not support AES instructions
  m_StreamConfig.encryptionFlags = ENCFLG_NONE;

  // Load the rikey and rikeyid into the stream configuration
  HexStringToBytes(rikey.c_str(), m_StreamConfig.remoteInputAesKey);
  int rikeyiv = htonl(stoi(rikeyid));
  memcpy(m_StreamConfig.remoteInputAesIv, &rikeyiv, sizeof(rikeyiv));

  // Manage gamepad input states based on selected settings
  HandleGamepadInputState(rumbleFeedback, mouseEmulation, flipABfaceButtons, flipXYfaceButtons);

  // Apply the desired latency mode ​based on the toggle switch state
  EmssLatencyMode selectedLatencyMode = gameMode ? EmssLatencyMode::kUltraLow : EmssLatencyMode::kLow;
  PostToJs(gameMode ? "Selecting the latency mode to: LATENCY_MODE_ULTRA_LOW" : "Selecting the latency mode to: LATENCY_MODE_LOW");
  // Create the media source with the selected latency and rendering modes
  m_Source = std::make_unique<samsung::wasm::ElementaryMediaStreamSource>(
    selectedLatencyMode,
    EmssRenderingMode::kMediaElement
  );
  // Set the source listener to the media source
  m_Source->SetListener(&m_SourceListener);

  // Store the parameters from the start message
  m_Host = host;
  m_HttpPort = httpPort;
  m_AppVersion = appversion;
  m_GfeVersion = gfeversion;
  m_RtspUrl = rtspurl;
  m_ServerCodecModeSupport = serverCodecModeSupport;
  m_FramePacingEnabled = framePacing;
  m_OptimizeGamesEnabled = optimizeGames;
  m_RumbleFeedbackEnabled = rumbleFeedback;
  m_MouseEmulationEnabled = mouseEmulation;
  m_FlipABfaceButtonsEnabled = flipABfaceButtons;
  m_FlipXYfaceButtonsEnabled = flipXYfaceButtons;
  m_AudioPacketDuration = audioPacketDuration;
  m_AudioJitterMs = audioJitterMs;
  m_PlayHostAudioEnabled = playHostAudio;
  m_HdrModeEnabled = hdrMode;
  m_FullRangeEnabled = fullRange;
  m_GameModeEnabled = gameMode;
  m_DisableWarningsEnabled = disableWarnings;
  m_PerformanceStatsEnabled = performanceStats;
  } catch (const std::exception& ex) {
    return failStartSetup(std::string("stream setup failed: ") + ex.what());
  } catch (...) {
    return failStartSetup("stream setup failed with an unknown exception");
  }

  // Initialize the rendering surface before starting the connection
  if (InitializeRenderingSurface(m_StreamConfig.width, m_StreamConfig.height)) {
    // Start the worker thread to establish the connection
    int err = pthread_create(&m_ConnectionThread, NULL, MoonlightInstance::ConnectionThreadFunc, this);
    if (err != 0) {
      ClLogMessage("Failed to create connection thread: attemptId=%u, error=%d\n", attemptId, err);
      m_ConnectionThreadCreated = false;
      CompleteStartFailure(attemptId, ML_ERROR_WASM_START_FAILED, std::string("failed to create connection thread: ") + std::to_string(err));
      return MessageResult::Reject(emscripten::val(err));
    }
    m_ConnectionThreadCreated = true;
    ClLogMessage("Connection thread created for host=%s:%d, attemptId=%u\n", m_Host.c_str(), m_HttpPort, attemptId);
  } else {
    ClLogMessage("Failed to initialize rendering surface: attemptId=%u, width=%d, height=%d\n",
      attemptId, m_StreamConfig.width, m_StreamConfig.height);
    // Failed to initialize renderer
    CompleteStartFailure(attemptId, ML_ERROR_WASM_START_FAILED, "failed to initialize rendering surface");
    return MessageResult::Reject(emscripten::val(std::string("failed to initialize rendering surface")));
  }

  return MessageResult::Resolve(emscripten::val(attemptId));
}

MessageResult MoonlightInstance::StopStream() {
  ClLogMessage("StopStream requested\n");

  // Begin connection teardown
  return StopConnection();
}

void MoonlightInstance::STUN_private(int callbackId) {
  unsigned int wanAddr;
  char addrStr[128] = {};

  if (LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &wanAddr) == 0) {
    inet_ntop(AF_INET, &wanAddr, addrStr, sizeof(addrStr));
    PostPromiseMessage(callbackId, "resolve", std::string(addrStr, strlen(addrStr)));
  } else {
    PostPromiseMessage(callbackId, "resolve", "");
  }
}

void MoonlightInstance::STUN(int callbackId) {
  m_Dispatcher.post_job(std::bind(&MoonlightInstance::STUN_private, this, callbackId), false);
}

void MoonlightInstance::Pair_private(int callbackId, std::string serverMajorVersion, std::string address, int httpPort, std::string randomNumber) {
  char* ppkstr;
  int err = gs_pair(atoi(serverMajorVersion.c_str()), address.c_str(), (unsigned short)httpPort, randomNumber.c_str(), &ppkstr);

  ClLogMessage("Paired host address: %s:%d using PIN: %s with result: %d\n", address.c_str(), httpPort, randomNumber.c_str(), err);
  if (err == 0) {
    PostPromiseMessage(callbackId, "resolve", ppkstr);
    free(ppkstr);
  } else {
    PostPromiseMessage(callbackId, "reject", std::to_string(err));
  }
}

void MoonlightInstance::Pair(int callbackId, std::string serverMajorVersion, std::string address, int httpPort, std::string randomNumber) {
  ClLogMessage("%s with host address: %s:%d\n", __func__, address.c_str(), httpPort);
  m_Dispatcher.post_job(std::bind(&MoonlightInstance::Pair_private, this, callbackId, serverMajorVersion, address, httpPort, randomNumber), false);
}

void MoonlightInstance::WakeOnLan(int callbackId, std::string macAddress) {
  unsigned char magicPacket[102];
  unsigned char mac[6];

  // Validate and parse the MAC address
  if (sscanf(macAddress.c_str(), "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx", &mac[0], &mac[1], &mac[2], &mac[3], &mac[4], &mac[5]) != 6) {
    ClLogMessage("Invalid MAC address format: %s\n", macAddress.c_str());
    return;
  }

  // Fill magic packet with the MAC address
  for (int i = 0; i < 6; i++) {
    magicPacket[i] = 0xFF;
  }
  for (int i = 1; i <= 16; i++) {
    memcpy(&magicPacket[i * 6], &mac, 6 * sizeof(unsigned char));
  }

  // Create UDP socket
  int udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (udpSocket == -1) {
    ClLogMessage("Failed to create socket");
    return;
  }

  // Enable broadcasting
  int broadcast = 1;
  if (setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast)) == -1) {
    ClLogMessage("Failed to enable broadcast");
    close(udpSocket);
    return;
  }

  // Set up destination address for the magic packet
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_BROADCAST;
  addr.sin_port = htons(9); // Wake-on-LAN typically uses port 9

  // Send the magic packet
  if (sendto(udpSocket, magicPacket, sizeof(magicPacket), 0, (struct sockaddr*) &addr, sizeof(addr)) == -1) {
    ClLogMessage("Failed to send magic packet");
  } else {
    ClLogMessage("Magic packet sent successfully to MAC address: %s\n", macAddress.c_str());
  }

  // Close the socket
  close(udpSocket);
}

bool MoonlightInstance::Init(uint32_t argc, const char* argn[], const char* argv[]) {
  g_Instance = this;
  return true;
}

int main(int argc, char** argv) {
  g_Instance = new MoonlightInstance();

  emscripten_set_keyup_callback(kCanvasName, NULL, EM_TRUE, handleKeyUp);
  emscripten_set_keydown_callback(kCanvasName, NULL, EM_TRUE, handleKeyDown);
  emscripten_set_mousedown_callback(kCanvasName, NULL, EM_TRUE, handleMouseDown);
  emscripten_set_mouseup_callback(kCanvasName, NULL, EM_TRUE, handleMouseUp);
  emscripten_set_mousemove_callback(kCanvasName, NULL, EM_TRUE, handleMouseMove);
  emscripten_set_wheel_callback(kCanvasName, NULL, EM_TRUE, handleWheel);

  // As we want to setup callbacks on DOM document and
  // emscripten_set_pointerlock... calls use document.querySelector
  // method, passing first argument to it, I've workaround for it
  // When passing address 0x1, js glue code replace it with document object
  static const char* kDocument = reinterpret_cast<const char*>(0x1);
  emscripten_set_pointerlockchange_callback(kDocument, NULL, EM_TRUE, handlePointerLockChange);
  emscripten_set_pointerlockerror_callback(kDocument, NULL, EM_TRUE, handlePointerLockError);
  EM_ASM(Module['noExitRuntime'] = true);
  unsigned char buffer[128];
  int rc = RAND_bytes(buffer, sizeof(buffer));

  if (rc != 1) {
    std::cout << "RAND_bytes failed\n";
  }
  RAND_seed(buffer, 128);
}

MessageResult startStream(std::string host, int httpPort, std::string width, std::string height, std::string fps, std::string bitrate,
  std::string rikey, std::string rikeyid, std::string appversion, std::string gfeversion, std::string rtspurl, int serverCodecModeSupport,
  bool framePacing, bool optimizeGames, bool rumbleFeedback, bool mouseEmulation, bool flipABfaceButtons, bool flipXYfaceButtons,
  std::string audioConfig, int audioPacketDuration, int audioJitterMs, bool playHostAudio, std::string videoCodec, bool hdrMode, bool fullRange, bool gameMode,
  bool disableWarnings, bool performanceStats) {
  MoonlightInstance::ClLogMessage("JS bridge invoked startStream: host=%s:%d, width=%s, height=%s, fps=%s, bitrate=%s\n",
    host.c_str(), httpPort, width.c_str(), height.c_str(), fps.c_str(), bitrate.c_str());
  PostToJs("Starting the streaming session...");
  return g_Instance->StartStream(host, httpPort, width, height, fps, bitrate, rikey, rikeyid, appversion, gfeversion, rtspurl, serverCodecModeSupport,
  framePacing, optimizeGames, rumbleFeedback, mouseEmulation, flipABfaceButtons, flipXYfaceButtons, audioConfig,
  audioPacketDuration, audioJitterMs, playHostAudio, videoCodec, hdrMode, fullRange, gameMode, disableWarnings, performanceStats);
}

MessageResult stopStream() {
  MoonlightInstance::ClLogMessage("JS bridge invoked stopStream\n");
  PostToJs("Stopping the streaming session...");
  return g_Instance->StopStream();
}

void toggleStats() {
  g_Instance->TogglePerformanceStats();
}

void stun(int callbackId) {
  g_Instance->STUN(callbackId);
}

void pair(int callbackId, std::string serverMajorVersion, std::string address, int httpPort, std::string randomNumber, std::string uniqueId) {
  if (g_UniqueId) {
    free(g_UniqueId);
  }
  g_UniqueId = strdup(uniqueId.c_str());
  g_Instance->Pair(callbackId, serverMajorVersion, address, httpPort, randomNumber);
}

void wakeOnLan(int callbackId, std::string macAddress) {
  g_Instance->WakeOnLan(callbackId, macAddress);
}

void PostToJs(std::string msg) {
  MAIN_THREAD_EM_ASM({
    const msg = UTF8ToString($0);
    handleMessage(msg);
  }, msg.c_str());
}

void PostToJsAsync(std::string msg) {
  MAIN_THREAD_ASYNC_EM_ASM({
    const msg = UTF8ToString($0);
    handleMessage(msg);
  }, msg.c_str());
}

void PostPromiseMessage(int callbackId, const std::string& type, const std::string& response) {
  MAIN_THREAD_EM_ASM({
    const type = UTF8ToString($1);
    const response = UTF8ToString($2);
    handlePromiseMessage($0, type, response);
  }, callbackId, type.c_str(), response.c_str());
}

void PostPromiseMessage(int callbackId, const std::string& type, const std::vector<uint8_t>& response) {
  MAIN_THREAD_EM_ASM({
    const type = UTF8ToString($1);
    const response = HEAPU8.slice($2, $2 + $3);
    handlePromiseMessage($0, type, response);
  }, callbackId, type.c_str(), response.data(), response.size());
}

EMSCRIPTEN_BINDINGS(handle_message) {
  emscripten::value_object<MessageResult>("MessageResult").field("type", &MessageResult::type).field("ret", &MessageResult::ret);
  emscripten::function("startStream", &startStream);
  emscripten::function("stopStream", &stopStream);
  emscripten::function("toggleStats", &toggleStats);
  emscripten::function("stun", &stun);
  emscripten::function("pair", &pair);
  emscripten::function("wakeOnLan", &wakeOnLan);
}
