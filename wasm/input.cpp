#include "moonlight_wasm.hpp"

#include <Limelight.h>

#define KEY_PREFIX 0x80

static int ConvertButtonToLiButton(unsigned short button) {
  switch (button) {
    case 0:
      return BUTTON_LEFT;
    case 1:
      return BUTTON_MIDDLE;
    case 2:
      return BUTTON_RIGHT;
    default:
      return 0;
  }
}

static char GetModifierFlags(const EmscriptenKeyboardEvent &event) {
  char flags = 0;

  if (event.ctrlKey == true) {
    flags |= MODIFIER_CTRL;
  }
  if (event.altKey == true) {
    flags |= MODIFIER_ALT;
  }
  if (event.shiftKey == true) {
    flags |= MODIFIER_SHIFT;
  }

  return flags;
}

EM_BOOL MoonlightInstance::HandleMouseDown(const EmscriptenMouseEvent &event) {
  if (!m_MouseLocked) {
    if (m_InputConfig.pointerCaptureMode == "disabled") {
      return EM_FALSE;
    }
    LockMouse();
    m_MouseLastPosX = event.screenX;
    m_MouseLastPosY = event.screenY;
    return EM_TRUE;
  }

  const int button = ConvertButtonToLiButton(event.button);
  if (button == 0 || event.button >= m_PhysicalMouseButtons.size()) {
    return EM_FALSE;
  }
  if (!m_PhysicalMouseButtons[event.button]) {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, button);
    m_PhysicalMouseButtons[event.button] = true;
  }
  return EM_TRUE;
}

EM_BOOL MoonlightInstance::HandleMouseMove(const EmscriptenMouseEvent &event) {
  if (!m_MouseLocked) {
    return EM_FALSE;
  }

  m_MouseDeltaX += event.movementX * m_InputConfig.physicalMouseSensitivity;
  m_MouseDeltaY += event.movementY * m_InputConfig.physicalMouseSensitivity;

  m_MouseLastPosX = event.screenX;
  m_MouseLastPosY = event.screenY;

  return EM_TRUE;
}

EM_BOOL MoonlightInstance::HandleMouseUp(const EmscriptenMouseEvent &event) {
  if (!m_MouseLocked) {
    return EM_FALSE;
  }

  const int button = ConvertButtonToLiButton(event.button);
  if (button == 0 || event.button >= m_PhysicalMouseButtons.size()) {
    return EM_FALSE;
  }
  if (m_PhysicalMouseButtons[event.button]) {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    m_PhysicalMouseButtons[event.button] = false;
  }
  return EM_TRUE;
}

EM_BOOL MoonlightInstance::HandleWheel(const EmscriptenWheelEvent &event) {
  if (!m_MouseLocked) {
    return EM_FALSE;
  }

  const float direction = m_InputConfig.invertMouseScroll ? 1.0f : -1.0f;
  m_AccumulatedTicks += event.deltaY * direction;
  return EM_TRUE;
}

EM_BOOL MoonlightInstance::HandleKeyDown(const EmscriptenKeyboardEvent &event) {
  if (!m_MouseLocked && !m_InputConfig.keyboardCaptureWithoutPointerLock) {
    return EM_FALSE;
  }

  char modifiers = GetModifierFlags(event);
  uint32_t keyCode = event.keyCode;

  const auto matchesShortcut = [&](const std::string& preset) {
    if (preset == "disabled") return false;
    const char required = preset == "compact"
      ? MODIFIER_CTRL | MODIFIER_SHIFT
      : MODIFIER_CTRL | MODIFIER_ALT | MODIFIER_SHIFT;
    return modifiers == required;
  };
  if (matchesShortcut(m_InputConfig.stopKeyboardShortcut) && keyCode == 0x51) {
    if (keyCode < m_ConsumedKeys.size()) m_ConsumedKeys[keyCode] = true;
    stopStream();
    return EM_TRUE;
  }
  if (matchesShortcut(m_InputConfig.statsKeyboardShortcut) && keyCode == 0x53) {
    if (keyCode < m_ConsumedKeys.size()) m_ConsumedKeys[keyCode] = true;
    toggleStats();
    return EM_TRUE;
  }
  if (modifiers == (MODIFIER_CTRL | MODIFIER_ALT | MODIFIER_SHIFT)) {
    m_WaitingForAllModifiersUp = true;
  }

  LiSendKeyboardEvent(KEY_PREFIX << 8 | keyCode, KEY_ACTION_DOWN, modifiers);
  if (keyCode < m_PressedKeys.size()) m_PressedKeys[keyCode] = true;
  return EM_TRUE;
}

EM_BOOL MoonlightInstance::HandleKeyUp(const EmscriptenKeyboardEvent &event) {
  if (!m_MouseLocked && !m_InputConfig.keyboardCaptureWithoutPointerLock) {
    return EM_FALSE;
  }

  char modifiers = GetModifierFlags(event);
  uint32_t keyCode = event.keyCode;

  if (keyCode < m_ConsumedKeys.size() && m_ConsumedKeys[keyCode]) {
    m_ConsumedKeys[keyCode] = false;
    return EM_TRUE;
  }

  // Check if all modifiers are up now
  if (m_WaitingForAllModifiersUp && modifiers == 0) {
    UnlockMouse();
    m_WaitingForAllModifiersUp = false;
  }

  LiSendKeyboardEvent(KEY_PREFIX << 8 | keyCode, KEY_ACTION_UP, modifiers);
  if (keyCode < m_PressedKeys.size()) m_PressedKeys[keyCode] = false;
  return EM_TRUE;
}

EM_BOOL handleKeyDown(int eventType, const EmscriptenKeyboardEvent *event, void *userData) {
  return g_Instance->HandleKeyDown(*event);
}

EM_BOOL handleKeyUp(int eventType, const EmscriptenKeyboardEvent *event, void *userData) {
  return g_Instance->HandleKeyUp(*event);
}

EM_BOOL handleMouseMove(int eventType, const EmscriptenMouseEvent *event, void *userData) {
  return g_Instance->HandleMouseMove(*event);
}

EM_BOOL handleMouseUp(int eventType, const EmscriptenMouseEvent *event, void *userData) {
  return g_Instance->HandleMouseUp(*event);
}

EM_BOOL handleMouseDown(int eventType, const EmscriptenMouseEvent *event, void *userData) {
  return g_Instance->HandleMouseDown(*event);
}

EM_BOOL handleWheel(int eventType, const EmscriptenWheelEvent *event, void *userData) {
  return g_Instance->HandleWheel(*event);
}

EM_BOOL handlePointerLockChange(int eventType, const EmscriptenPointerlockChangeEvent *pointerlockChangeEvent, void *userData) {
  if (!pointerlockChangeEvent) {
    return false;
  }

  if (pointerlockChangeEvent->isActive) {
    g_Instance->DidLockMouse(0);
  } else {
    g_Instance->MouseLockLost();
  }

  return true;
}

EM_BOOL handlePointerLockError(int eventType, const void *reserved, void *userData) {
  g_Instance->DidLockMouse(eventType);
  return true;
}

EM_BOOL handleWindowBlur(int eventType, const EmscriptenFocusEvent *event, void *userData) {
  g_Instance->ReleaseKeyboardAndMouse();
  return EM_TRUE;
}

void MoonlightInstance::ReportMouseMovement() {
  const int deltaX = static_cast<int>(m_MouseDeltaX);
  const int deltaY = static_cast<int>(m_MouseDeltaY);
  if (deltaX != 0 || deltaY != 0) {
    LiSendMouseMoveEvent(deltaX, deltaY);
    m_MouseDeltaX -= deltaX;
    m_MouseDeltaY -= deltaY;
  }

  if (m_AccumulatedTicks != 0) {
    // We can have fractional ticks here, so multiply by WHEEL_DELTA
    // to get actual scroll distance and use the high-res variant.
    LiSendHighResScrollEvent(m_AccumulatedTicks * 5);
    m_AccumulatedTicks = 0;
  }
}

void MoonlightInstance::LockMouse() {
  emscripten_request_pointerlock(kCanvasName, false);
}

void MoonlightInstance::UnlockMouse() {
  emscripten_exit_pointerlock();
}

void MoonlightInstance::DidLockMouse(int32_t result) {
  if (result != 0) {
    ClLogMessage("Error locking mouse, event type: %d\n", result);
  }

  m_MouseLocked = (result == 0);
  if (m_MouseLocked) {
    // Request an IDR frame to dump the frame queue that may have
    // built up from the GL pipeline being stalled.
    LiRequestIdrFrame();
  }
}

void MoonlightInstance::MouseLockLost() {
  m_MouseLocked = false;
  ReleaseKeyboardAndMouse();
}

void MoonlightInstance::ReleaseKeyboardAndMouse() {
  for (size_t button = 0; button < m_PhysicalMouseButtons.size(); ++button) {
    if (!m_PhysicalMouseButtons[button]) continue;
    LiSendMouseButtonEvent(
      BUTTON_ACTION_RELEASE,
      ConvertButtonToLiButton(static_cast<unsigned short>(button)));
    m_PhysicalMouseButtons[button] = false;
  }
  for (size_t key = 0; key < m_PressedKeys.size(); ++key) {
    if (m_PressedKeys[key]) {
      LiSendKeyboardEvent(
        KEY_PREFIX << 8 | static_cast<uint32_t>(key),
        KEY_ACTION_UP,
        0);
      m_PressedKeys[key] = false;
    }
    m_ConsumedKeys[key] = false;
  }
  m_WaitingForAllModifiersUp = false;
}

void sendKeyboardEvent(uint32_t keyCode, uint16_t action, char modifiers) {
  // Send a keyboard event to the host
  LiSendKeyboardEvent(KEY_PREFIX << 8 | keyCode, action, modifiers);
}

EMSCRIPTEN_BINDINGS(input) {
  emscripten::function("sendKeyboardEvent", &sendKeyboardEvent);
}
