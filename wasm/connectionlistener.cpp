#include "moonlight_wasm.hpp"

#include <cstdarg>
#include <cstring>
#include <string>

#include <emscripten.h>
#include <emscripten/threading.h>

namespace {

bool Contains(const char* message, const char* needle) {
  return std::strstr(message, needle) != nullptr;
}

const char* ClassifyNativeLogLevel(const char* message) {
  if (Contains(message, "error=0") &&
      (Contains(message, "OnConnectionStopped") ||
       Contains(message, "Connection listener reports stream terminated"))) {
    return "info";
  }

  if (Contains(message, "failed") || Contains(message, "Failed") ||
      Contains(message, "error") || Contains(message, "Error") ||
      Contains(message, "error=-") ||
      Contains(message, "Unable") || Contains(message, "Invalid") ||
      Contains(message, "malloc() failed") || Contains(message, "Terminating") ||
      Contains(message, "No audio traffic") ||
      Contains(message, "No video traffic")) {
    return "error";
  }

  if (Contains(message, "WARNING") || Contains(message, "Warning") ||
      Contains(message, "warning") || Contains(message, "dropped") ||
      Contains(message, "overflow") || Contains(message, "resync") ||
      Contains(message, "Slow connection")) {
    return "warn";
  }

  return "info";
}

} // namespace

void MoonlightInstance::ClStageStarting(int stage) {
  ClLogMessage("Connection stage starting: %s (%d)\n", LiGetStageName(stage), stage);
  PostToJs(std::string("ProgressMsg: Starting ") + std::string(LiGetStageName(stage)) + std::string("..."));
}

void MoonlightInstance::ClStageFailed(int stage, int errorCode) {
  ClLogMessage("Connection stage failed: %s (%d), error=%d\n", LiGetStageName(stage), stage, errorCode);
  PostToJs(std::string("DialogMsg: ") + std::string(LiGetStageName(stage)) + std::string(" failed (error ") + std::to_string(errorCode) + std::string(")"));
}

void MoonlightInstance::ClConnectionStarted(void) {
  ClLogMessage("Connection listener reports stream established\n");
  emscripten_sync_run_in_main_runtime_thread(EM_FUNC_SIG_V, onConnectionStarted);
}

void MoonlightInstance::ClConnectionTerminated(int errorCode) {
  ClLogMessage("Connection listener reports stream terminated, error=%d, lifecycle=%s, attemptId=%u\n",
    errorCode, g_Instance->GetLifecycleName(), g_Instance->GetStreamAttemptId());

  if (g_Instance->GetLifecycle() == StreamLifecycle::Stopping) {
    ClLogMessage("Connection termination callback suppressed because stop is already in progress: error=%d, attemptId=%u\n",
      errorCode, g_Instance->GetStreamAttemptId());
    return;
  }

  // Teardown the connection
  LiStopConnection();

  emscripten_sync_run_in_main_runtime_thread(EM_FUNC_SIG_VI, onConnectionStopped, errorCode);
}

void MoonlightInstance::ClDisplayMessage(const char* message) {
  ClLogMessage("Connection display message: %s\n", message);
  PostToJs(std::string("DialogMsg: ") + std::string(message));
}

void MoonlightInstance::ClDisplayTransientMessage(const char* message) {
  ClLogMessage("Connection transient message: %s\n", message);
  PostToJs(std::string("TransientMsg: ") + std::string(message));
}

void onConnectionStarted() {
  g_Instance->OnConnectionStarted(0);
}

void onConnectionStopped(int errorCode) {
  g_Instance->OnConnectionStopped(errorCode);
}

void MoonlightInstance::ClLogMessage(const char* format, ...) {
  va_list va;
  char message[1024];

  va_start(va, format);
  vsnprintf(message, sizeof(message), format, va);
  va_end(va);

  const char* level = ClassifyNativeLogLevel(message);
  MAIN_THREAD_EM_ASM({
    const level = UTF8ToString($0);
    const message = UTF8ToString($1).replace(/\s+$/, '');
    const root = typeof globalThis !== 'undefined' ? globalThis : window;
    const consoleObject = root.console || {};
    const logFunction = consoleObject[level] || consoleObject.log;
    if (typeof logFunction === 'function') {
      logFunction.call(consoleObject, '[native] ' + message);
    }
  }, level, message);
}

void MoonlightInstance::ClConnectionStatusUpdate(int connectionStatus) {
  ClLogMessage("Connection status update: status=%d, warningsDisabled=%d\n",
    connectionStatus, g_Instance->m_DisableWarningsEnabled);

  if (g_Instance->m_DisableWarningsEnabled == false) {
    switch (connectionStatus) {
      case CONN_STATUS_OKAY:
        PostToJs(std::string("NoWarningMsg: ") + std::string("Connection to PC has been improved."));
        break;
      case CONN_STATUS_POOR:
        PostToJs(std::string("WarningMsg: ") + std::string("Slow connection to PC.\nReduce your bitrate!"));
        break;
      default:
        break;
    }
  }
}

CONNECTION_LISTENER_CALLBACKS MoonlightInstance::s_ClCallbacks = {
  .stageStarting = MoonlightInstance::ClStageStarting,
  .stageFailed = MoonlightInstance::ClStageFailed,
  .connectionStarted = MoonlightInstance::ClConnectionStarted,
  .connectionTerminated = MoonlightInstance::ClConnectionTerminated,
  .logMessage = MoonlightInstance::ClLogMessage,
  .rumble = MoonlightInstance::ClControllerRumble,
  .connectionStatusUpdate = MoonlightInstance::ClConnectionStatusUpdate,
};
