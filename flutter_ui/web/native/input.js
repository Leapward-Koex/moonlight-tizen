(function installMoonlightInput(root) {
  'use strict';

  if (root.MoonlightInput) {
    return;
  }

  var ACTION_THRESHOLD = 0.5;
  var REPEAT_DELAY_MS = 350;
  var REPEAT_INTERVAL_MS = 100;
  var inputMode = 'ui';
  var inputSink = null;
  var gamepadFrame = null;
  var gamepadStates = {};
  var repeatTimers = {};
  var streamConfiguration = {};

  function emit(event) {
    if (typeof inputSink === 'function') {
      try {
        inputSink(event);
      } catch (error) {
        root.console.error('Moonlight input sink failed:', error);
      }
    }
    try {
      root.dispatchEvent(new CustomEvent('moonlight-input', { detail: event }));
    } catch (_) {
      // CustomEvent is not required by the native runtime.
    }
  }

  function clearRepeat(key) {
    if (key != null) {
      if (repeatTimers[key]) root.clearTimeout(repeatTimers[key].timer);
      delete repeatTimers[key];
      return;
    }
    Object.keys(repeatTimers).forEach(function(item) {
      root.clearTimeout(repeatTimers[item].timer);
    });
    repeatTimers = {};
  }

  function scheduleRepeat(key, action, source, detail) {
    clearRepeat(key);
    var state = { action: action, source: source, detail: detail || {}, timer: null };
    repeatTimers[key] = state;
    state.timer = root.setTimeout(function repeat() {
      if (repeatTimers[key] !== state || inputMode !== 'ui') {
        clearRepeat(key);
        return;
      }
      emit(Object.assign({
        type: 'action',
        action: state.action,
        phase: 'repeat',
        source: state.source
      }, state.detail));
      state.timer = root.setTimeout(repeat, REPEAT_INTERVAL_MS);
    }, REPEAT_DELAY_MS);
  }

  function emitAction(action, phase, source, detail) {
    emit(Object.assign({
      type: 'action',
      action: action,
      phase: phase || 'pressed',
      source: source
    }, detail || {}));
  }

  function normalizedKeyboardAction(event) {
    var keyCode = Number(event.keyCode || event.which || 0);
    var key = event.key || '';
    if (key === 'ArrowUp' || keyCode === 38) return 'up';
    if (key === 'ArrowDown' || keyCode === 40) return 'down';
    if (key === 'ArrowLeft' || keyCode === 37) return 'left';
    if (key === 'ArrowRight' || keyCode === 39) return 'right';
    if (key === 'Enter' || keyCode === 13 || keyCode === 32) return 'accept';
    if (key === 'Escape' || key === 'XF86Back' || keyCode === 10009) return 'back';
    if (keyCode === 427) return 'press';
    if (keyCode === 428) return 'switch';
    if (keyCode === 403) return 'stop';
    if (keyCode === 404) return 'toggleStats';
    return null;
  }

  function sendEscapeToHost(event) {
    if (event) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
    if (root.MoonlightNative && typeof root.MoonlightNative.sendEscape === 'function') {
      root.MoonlightNative.sendEscape();
    }
    var video = root.document.getElementById('wasm_module');
    if (video) {
      try {
        video.dispatchEvent(new MouseEvent('mousedown', {
          bubbles: true,
          cancelable: true,
          view: root,
          clientX: 0,
          clientY: 0
        }));
        video.focus();
      } catch (_) {
        // Focusing the video is best effort.
      }
    }
  }

  function onKeyDown(event) {
    var action = normalizedKeyboardAction(event);
    var keyCode = Number(event.keyCode || event.which || 0);

    if (keyCode === 447 || keyCode === 448 || keyCode === 449) {
      var volumeAction = keyCode === 447 ? 'up' : (keyCode === 448 ? 'down' : 'mute');
      if (root.MoonlightTizenPlatform) {
        root.MoonlightTizenPlatform.setVolume(volumeAction);
      }
      event.preventDefault();
      return;
    }

    if (!action || inputMode === 'disabled') {
      return;
    }

    if (inputMode === 'stream') {
      if (action === 'back') {
        sendEscapeToHost(event);
      } else if (action === 'stop' || action === 'toggleStats') {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (typeof inputSink === 'function') {
          emitAction(action, event.repeat ? 'repeat' : 'pressed', 'remote', { keyCode: keyCode });
        } else if (root.MoonlightNative) {
          if (action === 'stop') {
            root.MoonlightNative.stopStream().catch(function() {});
          } else {
            root.MoonlightNative.toggleStats().catch(function() {});
          }
        }
      }
      return;
    }

    // Flutter owns physical remote/keyboard navigation in UI mode. In
    // particular, it needs the original Arrow and Enter key events for focus
    // traversal and activation. The normalized sink is still used for
    // gamepad actions and Tizen-only actions that Flutter cannot reliably
    // receive as keyboard events (for example Back).
    if (typeof inputSink !== 'function') {
      return;
    }

    if (action === 'up' ||
        action === 'down' ||
        action === 'left' ||
        action === 'right' ||
        action === 'accept') {
      return;
    }

    event.preventDefault();
    emitAction(action, event.repeat ? 'repeat' : 'pressed', 'keyboard', { keyCode: keyCode });
  }

  function readGamepads() {
    if (!root.navigator) {
      return [];
    }
    var getter = root.navigator.getGamepads || root.navigator.webkitGetGamepads;
    if (typeof getter !== 'function') {
      return [];
    }
    return getter.call(root.navigator) || [];
  }

  function isRealGamepad(gamepad) {
    return !!(gamepad && gamepad.connected !== false && Number(gamepad.timestamp || 0) !== 0);
  }

  function connectedGamepadMask() {
    var count = 0;
    var mask = 0;
    var gamepads = readGamepads();
    for (var index = 0; index < gamepads.length; index += 1) {
      if (isRealGamepad(gamepads[index])) {
        mask |= 1 << count;
        count += 1;
      }
    }
    return mask;
  }

  function fingerprint(value) {
    var hash = 0x811c9dc5;
    var text = String(value || '');
    for (var index = 0; index < text.length; index += 1) {
      hash ^= text.charCodeAt(index) & 0xff;
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return ('00000000' + hash.toString(16)).slice(-8);
  }

  function inputDevices() {
    var devices = [];
    var gamepads = readGamepads();
    for (var index = 0; index < gamepads.length && devices.length < 4; index += 1) {
      var gamepad = gamepads[index];
      if (!isRealGamepad(gamepad)) continue;
      var actuator = gamepad.vibrationActuator ||
        (gamepad.hapticActuators && gamepad.hapticActuators[0]);
      devices.push({
        slot: devices.length,
        browserIndex: gamepad.index,
        fingerprint: fingerprint(gamepad.id),
        id: gamepad.id || ('Controller ' + (devices.length + 1)),
        mapping: gamepad.mapping || 'unknown',
        buttonCount: (gamepad.buttons || []).length,
        axisCount: (gamepad.axes || []).length,
        supportsRumble: !!actuator,
        pressedButtons: Array.prototype.map.call(gamepad.buttons || [], function(button, buttonIndex) {
          return button.pressed ? buttonIndex : -1;
        }).filter(function(buttonIndex) { return buttonIndex >= 0; }),
        axes: Array.prototype.map.call(gamepad.axes || [], function(axis) {
          return Math.round(Number(axis || 0) * 100) / 100;
        })
      });
    }
    return devices;
  }

  function testRumble(browserIndex) {
    var gamepads = readGamepads();
    var gamepad = gamepads[browserIndex];
    var actuator = gamepad && (gamepad.vibrationActuator ||
      (gamepad.hapticActuators && gamepad.hapticActuators[0]));
    if (!actuator) return false;
    try {
      if (typeof actuator.playEffect === 'function') {
        Promise.resolve(actuator.playEffect('dual-rumble', {
          startDelay: 0,
          duration: 350,
          weakMagnitude: 0.5,
          strongMagnitude: 0.8
        })).catch(function() {});
        return true;
      }
      if (typeof actuator.pulse === 'function') {
        actuator.pulse(0.8, 350);
        return true;
      }
    } catch (_) {}
    return false;
  }

  function buttonAction(index) {
    return {
      0: 'accept',
      1: 'back',
      8: 'press',
      9: 'switch',
      12: 'up',
      13: 'down',
      14: 'left',
      15: 'right'
    }[index] || null;
  }

  function axisAction(axis, value) {
    if (axis === 0 && value < -ACTION_THRESHOLD) return 'left';
    if (axis === 0 && value > ACTION_THRESHOLD) return 'right';
    if (axis === 1 && value < -ACTION_THRESHOLD) return 'up';
    if (axis === 1 && value > ACTION_THRESHOLD) return 'down';
    return null;
  }

  function captureGamepadState(gamepad) {
    return {
      buttons: Array.prototype.map.call(gamepad.buttons || [], function(button) {
        return !!button.pressed;
      }),
      axes: Array.prototype.slice.call(gamepad.axes || [])
    };
  }

  function pollGamepads() {
    var gamepads = readGamepads();
    var present = {};

    for (var index = 0; index < gamepads.length; index += 1) {
      var gamepad = gamepads[index];
      if (!isRealGamepad(gamepad)) {
        continue;
      }
      present[gamepad.index] = true;
      var previous = gamepadStates[gamepad.index];
      var current = captureGamepadState(gamepad);

      if (!previous) {
        gamepadStates[gamepad.index] = current;
        emit({
          type: 'gamepad-connected',
          source: 'gamepad',
          index: gamepad.index,
          id: gamepad.id || '',
          connectedMask: connectedGamepadMask()
        });
        continue;
      }

      if (inputMode === 'ui') {
        for (var buttonIndex = 0; buttonIndex < current.buttons.length; buttonIndex += 1) {
          if (current.buttons[buttonIndex] === previous.buttons[buttonIndex]) {
            continue;
          }
          emit({
            type: 'controller-button',
            phase: current.buttons[buttonIndex] ? 'pressed' : 'released',
            source: 'gamepad',
            gamepadIndex: gamepad.index,
            controlIndex: buttonIndex
          });
          var action = buttonAction(buttonIndex);
          if (!action) {
            continue;
          }
          if (current.buttons[buttonIndex]) {
            emitAction(action, 'pressed', 'gamepad', {
              gamepadIndex: gamepad.index,
              controlIndex: buttonIndex
            });
            scheduleRepeat('b' + gamepad.index + ':' + buttonIndex, action, 'gamepad', {
              gamepadIndex: gamepad.index,
              controlIndex: buttonIndex
            });
          } else {
            emitAction(action, 'released', 'gamepad', {
              gamepadIndex: gamepad.index,
              controlIndex: buttonIndex
            });
            clearRepeat('b' + gamepad.index + ':' + buttonIndex);
          }
        }

        for (var axisIndex = 0; axisIndex < Math.min(2, current.axes.length); axisIndex += 1) {
          var currentAction = axisAction(axisIndex, current.axes[axisIndex]);
          var previousAction = axisAction(axisIndex, previous.axes[axisIndex] || 0);
          if (currentAction === previousAction) {
            continue;
          }
          if (currentAction) {
            emitAction(currentAction, 'pressed', 'gamepad', {
              gamepadIndex: gamepad.index,
              controlIndex: axisIndex,
              value: current.axes[axisIndex]
            });
            scheduleRepeat('a' + gamepad.index + ':' + axisIndex, currentAction, 'gamepad', {
              gamepadIndex: gamepad.index,
              controlIndex: axisIndex,
              value: current.axes[axisIndex]
            });
          } else {
            clearRepeat('a' + gamepad.index + ':' + axisIndex);
          }
        }
      }

      gamepadStates[gamepad.index] = current;
    }

    Object.keys(gamepadStates).forEach(function(index) {
      if (!present[index]) {
        delete gamepadStates[index];
        clearRepeat();
        emit({
          type: 'gamepad-disconnected',
          source: 'gamepad',
          index: Number(index),
          connectedMask: connectedGamepadMask()
        });
      }
    });

    gamepadFrame = root.requestAnimationFrame(pollGamepads);
  }

  function setInputMode(mode) {
    if (mode !== 'ui' && mode !== 'stream' && mode !== 'disabled') {
      throw new Error('Unknown Moonlight input mode: ' + mode);
    }
    inputMode = mode;
    clearRepeat();
    var video = root.document.getElementById('wasm_module');
    if (mode === 'stream' && video) {
      video.focus();
      if (streamConfiguration.pointerCaptureMode === 'streamStart' &&
          typeof video.requestPointerLock === 'function') {
        try {
          var result = video.requestPointerLock();
          if (result && typeof result.catch === 'function') result.catch(function() {});
        } catch (_) {}
      }
    }
    return inputMode;
  }

  function setInputSink(sink) {
    inputSink = typeof sink === 'function' ? sink : null;
  }

  function setConfiguration(configuration) {
    streamConfiguration = configuration && typeof configuration === 'object'
      ? configuration
      : {};
    return streamConfiguration;
  }

  root.document.addEventListener('keydown', onKeyDown, true);
  if (root.MoonlightTizenPlatform) {
    root.MoonlightTizenPlatform.registerKeys();
  }
  gamepadFrame = root.requestAnimationFrame(pollGamepads);

  root.MoonlightInput = Object.freeze({
    setMode: setInputMode,
    getMode: function() { return inputMode; },
    setSink: setInputSink,
    requestAction: function(action, source) {
      emitAction(action, 'pressed', source || 'ui');
      return true;
    },
    connectedGamepadMask: connectedGamepadMask,
    inputDevices: inputDevices,
    testRumble: testRumble,
    setConfiguration: setConfiguration,
    sendEscapeToHost: sendEscapeToHost,
    stop: function() {
      clearRepeat();
      if (gamepadFrame !== null) {
        root.cancelAnimationFrame(gamepadFrame);
        gamepadFrame = null;
      }
    }
  });
})(window);
