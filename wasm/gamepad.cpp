#include "moonlight_wasm.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

#include <Limelight.h>
#include <emscripten/emscripten.h>

namespace {

constexpr int kMaxControllers = 4;
constexpr auto kMouseToggleHold = std::chrono::milliseconds(1000);

float ClampFloat(float value, float minimum, float maximum) {
  return std::max(minimum, std::min(maximum, value));
}

std::vector<std::string> Split(const std::string& value, char delimiter) {
  std::vector<std::string> parts;
  std::stringstream stream(value);
  std::string part;
  while (std::getline(stream, part, delimiter)) {
    parts.push_back(part);
  }
  if (!value.empty() && value.back() == delimiter) {
    parts.emplace_back();
  }
  return parts;
}

float ParseFloat(const std::vector<std::string>& parts, size_t index, float fallback) {
  if (index >= parts.size()) return fallback;
  try {
    return std::stof(parts[index]);
  } catch (...) {
    return fallback;
  }
}

bool ParseBool(const std::vector<std::string>& parts, size_t index, bool fallback) {
  if (index >= parts.size()) return fallback;
  return parts[index] == "1" ? true : parts[index] == "0" ? false : fallback;
}

uint32_t GamepadFingerprint(const char* id) {
  uint32_t hash = 2166136261u;
  if (!id) return hash;
  for (const unsigned char* cursor = reinterpret_cast<const unsigned char*>(id); *cursor; ++cursor) {
    hash ^= *cursor;
    hash *= 16777619u;
  }
  return hash;
}

InputConfiguration ParseInputConfiguration(const std::string& wire) {
  InputConfiguration config;
  const auto parts = Split(wire, '|');
  if (parts.empty() || parts[0] != "v1") return config;
  if (parts.size() > 1 && !parts[1].empty()) config.controllerLayout = parts[1];
  config.stickDeadzone = ClampFloat(ParseFloat(parts, 2, config.stickDeadzone), 0.0f, 0.5f);
  config.triggerThreshold = ClampFloat(ParseFloat(parts, 3, config.triggerThreshold), 0.0f, 0.95f);
  config.controllerSensitivity = ClampFloat(ParseFloat(parts, 4, config.controllerSensitivity), 0.5f, 2.0f);
  config.invertControllerYAxis = ParseBool(parts, 5, config.invertControllerYAxis);
  config.mouseEmulationSpeed = ClampFloat(ParseFloat(parts, 6, config.mouseEmulationSpeed), 0.25f, 3.0f);
  config.mouseAcceleration = ClampFloat(ParseFloat(parts, 7, config.mouseAcceleration), 0.5f, 2.5f);
  config.mouseScrollSpeed = ClampFloat(ParseFloat(parts, 8, config.mouseScrollSpeed), 0.25f, 5.0f);
  if (parts.size() > 9 && !parts[9].empty()) config.mouseActivationButton = parts[9];
  config.physicalMouseSensitivity = ClampFloat(ParseFloat(parts, 10, config.physicalMouseSensitivity), 0.25f, 3.0f);
  config.invertMouseScroll = ParseBool(parts, 11, config.invertMouseScroll);
  config.keyboardCaptureWithoutPointerLock = ParseBool(parts, 12, config.keyboardCaptureWithoutPointerLock);
  if (parts.size() > 13 && !parts[13].empty()) config.pointerCaptureMode = parts[13];
  if (parts.size() > 14 && !parts[14].empty()) config.stopControllerShortcut = parts[14];
  if (parts.size() > 15 && !parts[15].empty()) config.statsControllerShortcut = parts[15];
  if (parts.size() > 16 && !parts[16].empty()) config.stopKeyboardShortcut = parts[16];
  if (parts.size() > 17 && !parts[17].empty()) config.statsKeyboardShortcut = parts[17];
  if (parts.size() > 18) {
    for (const auto& profile : Split(parts[18], ',')) {
      const auto separator = profile.find(':');
      if (separator == std::string::npos) continue;
      try {
        const auto fingerprint = static_cast<uint32_t>(std::stoul(profile.substr(0, separator), nullptr, 16));
        config.controllerProfiles[fingerprint] = profile.substr(separator + 1);
      } catch (...) {
      }
    }
  }
  return config;
}

enum GamepadButton {
  A, B, X, Y,
  LeftBumper, RightBumper,
  LeftTrigger, RightTrigger,
  Back, Play,
  LeftStick, RightStick,
  Up, Down, Left, Right,
  Special,
  Count,
};

enum GamepadAxis { LeftX = 0, LeftY = 1, RightX = 2, RightY = 3 };

const int kButtonMasksDefault[] = {
  A_FLAG, B_FLAG, X_FLAG, Y_FLAG, LB_FLAG, RB_FLAG, 0, 0,
  BACK_FLAG, PLAY_FLAG, LS_CLK_FLAG, RS_CLK_FLAG,
  UP_FLAG, DOWN_FLAG, LEFT_FLAG, RIGHT_FLAG, SPECIAL_FLAG,
};
const int kButtonMasksAB[] = {
  B_FLAG, A_FLAG, X_FLAG, Y_FLAG, LB_FLAG, RB_FLAG, 0, 0,
  BACK_FLAG, PLAY_FLAG, LS_CLK_FLAG, RS_CLK_FLAG,
  UP_FLAG, DOWN_FLAG, LEFT_FLAG, RIGHT_FLAG, SPECIAL_FLAG,
};
const int kButtonMasksXY[] = {
  A_FLAG, B_FLAG, Y_FLAG, X_FLAG, LB_FLAG, RB_FLAG, 0, 0,
  BACK_FLAG, PLAY_FLAG, LS_CLK_FLAG, RS_CLK_FLAG,
  UP_FLAG, DOWN_FLAG, LEFT_FLAG, RIGHT_FLAG, SPECIAL_FLAG,
};
const int kButtonMasksABXY[] = {
  B_FLAG, A_FLAG, Y_FLAG, X_FLAG, LB_FLAG, RB_FLAG, 0, 0,
  BACK_FLAG, PLAY_FLAG, LS_CLK_FLAG, RS_CLK_FLAG,
  UP_FLAG, DOWN_FLAG, LEFT_FLAG, RIGHT_FLAG, SPECIAL_FLAG,
};

short GetButtonFlags(const EmscriptenGamepadEvent& gamepad,
                     const InputConfiguration& config,
                     bool legacyFlipAB,
                     bool legacyFlipXY) {
  std::string layout = config.controllerLayout;
  const auto profile = config.controllerProfiles.find(GamepadFingerprint(gamepad.id));
  if (profile != config.controllerProfiles.end() && profile->second != "automatic") {
    layout = profile->second;
  }

  bool flipAB = false;
  bool flipXY = false;
  if (layout == "nintendo") {
    flipAB = true;
    flipXY = true;
  } else if (layout == "custom" || layout == "automatic") {
    flipAB = legacyFlipAB;
    flipXY = legacyFlipXY;
  }

  const int* masks = flipAB && flipXY ? kButtonMasksABXY
                    : flipAB ? kButtonMasksAB
                    : flipXY ? kButtonMasksXY
                    : kButtonMasksDefault;
  const int maskCount = static_cast<int>(sizeof(kButtonMasksDefault) / sizeof(kButtonMasksDefault[0]));
  short result = 0;
  for (int index = 0; index < gamepad.numButtons && index < maskCount; ++index) {
    if (gamepad.digitalButton[index] == EM_TRUE) result |= masks[index];
  }
  return result;
}

float ReadAxis(const EmscriptenGamepadEvent& gamepad, int index) {
  return index < gamepad.numAxes ? ClampFloat(static_cast<float>(gamepad.axis[index]), -1.0f, 1.0f) : 0.0f;
}

float ReadTrigger(const EmscriptenGamepadEvent& gamepad, int index, const InputConfiguration& config) {
  if (index >= gamepad.numButtons) return 0.0f;
  const float value = ClampFloat(static_cast<float>(gamepad.analogButton[index]), 0.0f, 1.0f);
  if (value <= config.triggerThreshold) return 0.0f;
  return (value - config.triggerThreshold) / (1.0f - config.triggerThreshold);
}

void ApplyStick(float& x, float& y, const InputConfiguration& config) {
  const float magnitude = std::sqrt(x * x + y * y);
  if (magnitude <= config.stickDeadzone || magnitude <= 0.0001f) {
    x = 0;
    y = 0;
    return;
  }
  const float normalized = ClampFloat((magnitude - config.stickDeadzone) / (1.0f - config.stickDeadzone), 0.0f, 1.0f);
  const float shaped = std::pow(normalized, 1.0f / config.controllerSensitivity);
  const float scale = shaped / magnitude;
  x = ClampFloat(x * scale, -1.0f, 1.0f);
  y = ClampFloat(y * scale, -1.0f, 1.0f);
}

short ControllerShortcutMask(const std::string& preset, bool statistics) {
  if (preset == "disabled") return 0;
  if (preset == "simplified") return statistics ? BACK_FLAG | X_FLAG : BACK_FLAG | PLAY_FLAG;
  return statistics ? BACK_FLAG | LB_FLAG | RB_FLAG | X_FLAG
                    : BACK_FLAG | PLAY_FLAG | LB_FLAG | RB_FLAG;
}

short ActivationMask(const std::string& button) {
  if (button == "back") return BACK_FLAG;
  if (button == "leftStick") return LS_CLK_FLAG;
  if (button == "rightStick") return RS_CLK_FLAG;
  return PLAY_FLAG;
}

struct PolledGamepad {
  int browserIndex;
  EmscriptenGamepadEvent event;
};

}  // namespace

void MoonlightInstance::HandleGamepadInputState(bool rumbleFeedback,
                                                 bool mouseEmulation,
                                                 bool flipABfaceButtons,
                                                 bool flipXYfaceButtons) {
  m_RumbleFeedbackEnabled = rumbleFeedback;
  m_MouseEmulationEnabled = mouseEmulation;
  m_FlipABfaceButtonsEnabled = flipABfaceButtons;
  m_FlipXYfaceButtonsEnabled = flipXYfaceButtons;
  m_LastGamepadPoll = std::chrono::steady_clock::now();
}

void MoonlightInstance::ConfigureInput(const std::string& inputConfiguration) {
  m_InputConfig = ParseInputConfiguration(inputConfiguration);
}

void MoonlightInstance::SetEmulatedMouseButton(int index, bool pressed) {
  if (index < 0 || index >= static_cast<int>(m_EmulatedMouseButtons.size())) return;
  if (m_EmulatedMouseButtons[index] == pressed) return;
  static const int buttons[] = {BUTTON_LEFT, BUTTON_MIDDLE, BUTTON_RIGHT};
  LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, buttons[index]);
  m_EmulatedMouseButtons[index] = pressed;
}

void MoonlightInstance::DeactivateMouseEmulation() {
  if (m_MouseEmulationControllerSlot >= 0) {
    PostToJs(std::string("mouseEmulationOff"));
  }
  SetEmulatedMouseButton(0, false);
  SetEmulatedMouseButton(1, false);
  SetEmulatedMouseButton(2, false);
  m_MouseEmulationControllerSlot = -1;
  m_MouseScrollRemainderX = 0;
  m_MouseScrollRemainderY = 0;
}

void MoonlightInstance::PollGamepads() {
  if (emscripten_sample_gamepad_data() != EMSCRIPTEN_RESULT_SUCCESS) return;
  const int reportedCount = emscripten_get_num_gamepads();
  if (reportedCount < 0) return;

  std::vector<PolledGamepad> connected;
  for (int browserIndex = 0; browserIndex < reportedCount; ++browserIndex) {
    EmscriptenGamepadEvent event{};
    if (emscripten_get_gamepad_status(browserIndex, &event) != EMSCRIPTEN_RESULT_SUCCESS ||
        !event.connected || event.timestamp == 0) {
      continue;
    }
    connected.push_back({browserIndex, event});
  }

  auto findEvent = [&](int browserIndex) -> const EmscriptenGamepadEvent* {
    for (const auto& item : connected) {
      if (item.browserIndex == browserIndex) return &item.event;
    }
    return nullptr;
  };
  auto hasSlot = [&](int browserIndex) {
    return std::find(m_GamepadBrowserIndices.begin(), m_GamepadBrowserIndices.end(), browserIndex) != m_GamepadBrowserIndices.end();
  };

  std::array<bool, kMaxControllers> disconnectedSlots{};
  for (int slot = 0; slot < kMaxControllers; ++slot) {
    if (m_GamepadBrowserIndices[slot] >= 0 && !findEvent(m_GamepadBrowserIndices[slot])) {
      disconnectedSlots[slot] = true;
      m_GamepadBrowserIndices[slot] = -1;
      m_LastControllerButtons[slot] = 0;
      m_MouseToggleHeld[slot] = false;
      m_MouseToggleConsumed[slot] = false;
      m_StatsComboLatched[slot] = false;
      if (m_MouseEmulationControllerSlot == slot) DeactivateMouseEmulation();
    }
  }
  for (const auto& item : connected) {
    if (hasSlot(item.browserIndex)) continue;
    const auto freeSlot = std::find(m_GamepadBrowserIndices.begin(), m_GamepadBrowserIndices.end(), -1);
    if (freeSlot == m_GamepadBrowserIndices.end()) break;
    *freeSlot = item.browserIndex;
  }

  short activeMask = 0;
  for (int slot = 0; slot < kMaxControllers; ++slot) {
    if (m_GamepadBrowserIndices[slot] >= 0) activeMask |= static_cast<short>(1 << slot);
  }
  for (int slot = 0; slot < kMaxControllers; ++slot) {
    if (disconnectedSlots[slot]) {
      LiSendMultiControllerEvent(slot, activeMask, 0, 0, 0, 0, 0, 0, 0);
    }
  }

  const auto now = std::chrono::steady_clock::now();
  float elapsed = std::chrono::duration<float>(now - m_LastGamepadPoll).count();
  elapsed = ClampFloat(elapsed, 0.001f, 0.05f);
  m_LastGamepadPoll = now;

  if (!m_MouseEmulationEnabled) DeactivateMouseEmulation();

  for (int slot = 0; slot < kMaxControllers; ++slot) {
    const auto* gamepad = findEvent(m_GamepadBrowserIndices[slot]);
    if (!gamepad) continue;

    short buttons = GetButtonFlags(*gamepad, m_InputConfig,
                                   m_FlipABfaceButtonsEnabled,
                                   m_FlipXYfaceButtonsEnabled);
    const short stopMask = ControllerShortcutMask(m_InputConfig.stopControllerShortcut, false);
    const short statsMask = ControllerShortcutMask(m_InputConfig.statsControllerShortcut, true);
    if (stopMask && (buttons & stopMask) == stopMask) {
      stopStream();
      return;
    }
    const bool statsPressed = statsMask && (buttons & statsMask) == statsMask;
    if (statsPressed && !m_StatsComboLatched[slot]) toggleStats();
    m_StatsComboLatched[slot] = statsPressed;

    float leftX = ReadAxis(*gamepad, GamepadAxis::LeftX);
    float leftY = -ReadAxis(*gamepad, GamepadAxis::LeftY);
    float rightX = ReadAxis(*gamepad, GamepadAxis::RightX);
    float rightY = -ReadAxis(*gamepad, GamepadAxis::RightY);
    ApplyStick(leftX, leftY, m_InputConfig);
    ApplyStick(rightX, rightY, m_InputConfig);
    if (m_InputConfig.invertControllerYAxis) {
      leftY = -leftY;
      rightY = -rightY;
    }

    const short activation = ActivationMask(m_InputConfig.mouseActivationButton);
    const bool activationPressed = (buttons & activation) != 0;
    if (m_MouseEmulationEnabled && activationPressed) {
      if (!m_MouseToggleHeld[slot]) {
        m_MouseToggleHeld[slot] = true;
        m_MouseToggleConsumed[slot] = false;
        m_MouseToggleStarted[slot] = now;
      } else if (!m_MouseToggleConsumed[slot] && now - m_MouseToggleStarted[slot] >= kMouseToggleHold) {
        m_MouseToggleConsumed[slot] = true;
        LiSendMultiControllerEvent(slot, activeMask, 0, 0, 0, 0, 0, 0, 0);
        m_LastControllerButtons[slot] = 0;
        if (m_MouseEmulationControllerSlot == slot) {
          DeactivateMouseEmulation();
        } else {
          DeactivateMouseEmulation();
          m_MouseEmulationControllerSlot = slot;
          PostToJs(std::string("mouseEmulationOn"));
        }
      }
    } else if (!activationPressed) {
      m_MouseToggleHeld[slot] = false;
      m_MouseToggleConsumed[slot] = false;
    }

    if (m_MouseToggleConsumed[slot]) buttons &= ~activation;

    if (m_MouseEmulationControllerSlot == slot) {
      const float leftMagnitude = std::sqrt(leftX * leftX + leftY * leftY);
      if (leftMagnitude > 0.0001f) {
        const float curve = std::pow(ClampFloat(leftMagnitude, 0.0f, 1.0f), m_InputConfig.mouseAcceleration);
        const float pixels = 900.0f * m_InputConfig.mouseEmulationSpeed * curve * elapsed;
        m_MouseDeltaX += leftX / leftMagnitude * pixels;
        m_MouseDeltaY -= leftY / leftMagnitude * pixels;
      }

      const float scrollScale = 20.0f * m_InputConfig.mouseScrollSpeed * elapsed;
      m_MouseScrollRemainderX += rightX * scrollScale;
      m_MouseScrollRemainderY += rightY * scrollScale;
      const int scrollX = static_cast<int>(m_MouseScrollRemainderX);
      const int scrollY = static_cast<int>(m_MouseScrollRemainderY);
      if (scrollX != 0) {
        LiSendHScrollEvent(scrollX);
        m_MouseScrollRemainderX -= scrollX;
      }
      if (scrollY != 0) {
        LiSendScrollEvent(scrollY);
        m_MouseScrollRemainderY -= scrollY;
      }
      SetEmulatedMouseButton(0, (buttons & (A_FLAG | LB_FLAG)) != 0);
      SetEmulatedMouseButton(1, (buttons & (X_FLAG | Y_FLAG)) != 0);
      SetEmulatedMouseButton(2, (buttons & (B_FLAG | RB_FLAG)) != 0);
      continue;
    }

    const auto leftTrigger = static_cast<unsigned char>(std::lround(
      ReadTrigger(*gamepad, GamepadButton::LeftTrigger, m_InputConfig) * std::numeric_limits<unsigned char>::max()));
    const auto rightTrigger = static_cast<unsigned char>(std::lround(
      ReadTrigger(*gamepad, GamepadButton::RightTrigger, m_InputConfig) * std::numeric_limits<unsigned char>::max()));
    const auto toShort = [](float value) {
      return static_cast<short>(std::lround(value * std::numeric_limits<short>::max()));
    };
    LiSendMultiControllerEvent(slot, activeMask, buttons, leftTrigger, rightTrigger,
                               toShort(leftX), toShort(leftY), toShort(rightX), toShort(rightY));
    m_LastControllerButtons[slot] = buttons;
  }
}

void MoonlightInstance::ReleaseAllInput() {
  DeactivateMouseEmulation();
  for (int slot = 0; slot < kMaxControllers; ++slot) {
    if (m_GamepadBrowserIndices[slot] >= 0 || m_LastControllerButtons[slot] != 0) {
      LiSendMultiControllerEvent(slot, 0, 0, 0, 0, 0, 0, 0, 0);
    }
    m_GamepadBrowserIndices[slot] = -1;
    m_LastControllerButtons[slot] = 0;
    m_MouseToggleHeld[slot] = false;
    m_MouseToggleConsumed[slot] = false;
    m_StatsComboLatched[slot] = false;
  }
  for (size_t key = 0; key < m_PressedKeys.size(); ++key) {
    if (m_PressedKeys[key]) {
      LiSendKeyboardEvent(0x8000u | static_cast<uint32_t>(key), KEY_ACTION_UP, 0);
      m_PressedKeys[key] = false;
    }
    m_ConsumedKeys[key] = false;
  }
}

void MoonlightInstance::ClControllerRumble(unsigned short controllerNumber,
                                            unsigned short lowFreqMotor,
                                            unsigned short highFreqMotor) {
  if (!g_Instance || !g_Instance->m_RumbleFeedbackEnabled || controllerNumber >= kMaxControllers) return;
  const int browserIndex = g_Instance->m_GamepadBrowserIndices[controllerNumber];
  if (browserIndex < 0) return;
  const float weakMagnitude = static_cast<float>(highFreqMotor) / UINT16_MAX;
  const float strongMagnitude = static_cast<float>(lowFreqMotor) / UINT16_MAX;
  std::ostringstream message;
  message << browserIndex << "," << weakMagnitude << "," << strongMagnitude;
  PostToJs(std::string("controllerRumble: ") + message.str());
}
