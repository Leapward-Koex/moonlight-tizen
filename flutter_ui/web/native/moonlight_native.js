(function installMoonlightNative(root) {
  'use strict';

  if (root.MoonlightNative && root.MoonlightNative.bridgeVersion) {
    return;
  }

  var BRIDGE_VERSION = 1;
  var RUNTIME_SCRIPT = 'moonlight-wasm.js';
  var RUNTIME_SCRIPT_ID = 'moonlight-wasm-runtime';
  var RUNTIME_TIMEOUT_MS = 60000;
  var STREAM_START_TIMEOUT_MS = 60000;
  var runtimeReady = false;
  var runtimeState = 'uninitialized';
  var runtimePromise = null;
  var runtimeResolve = null;
  var runtimeReject = null;
  var moduleRef = null;
  var eventSink = null;
  var callbackId = 1;
  var asyncCallbacks = {};
  var pendingStreamStart = null;
  var activeStreamAttemptId = null;
  var earlyStreamResult = null;
  var transientTimer = null;

  function debug(level, eventName, details) {
    if (typeof root.moonlightDebugLog === 'function') {
      root.moonlightDebugLog(level, eventName, Object.assign({
        source: 'native/moonlight_native.js'
      }, details || {}));
      return;
    }
    var logger = root.console && (root.console[level] || root.console.log);
    if (typeof logger === 'function') {
      logger.call(root.console, '[MoonlightNative] ' + eventName, details || '');
    }
  }

  function emit(event) {
    var value = Object.assign({ timestamp: Date.now() }, event || {});
    if (typeof eventSink === 'function') {
      try {
        eventSink(value);
      } catch (error) {
        debug('error', 'event sink threw', {
          error: error && error.message ? error.message : String(error),
          eventType: value.type
        });
      }
    }
    try {
      root.dispatchEvent(new CustomEvent('moonlight-native-event', { detail: value }));
    } catch (_) {
      // CustomEvent is a convenience for browser diagnostics, not a runtime dependency.
    }
  }

  function nativeError(message, code, details) {
    var error = new Error(message || 'Moonlight native operation failed.');
    error.code = code || 'native-error';
    if (details) {
      error.details = details;
    }
    return error;
  }

  function element(id) {
    return root.document && root.document.getElementById(id);
  }

  function setHidden(target, hidden) {
    if (target) {
      target.hidden = !!hidden;
    }
  }

  function clearStreamOverlays() {
    setHidden(element('stream-loading'), true);
    setHidden(element('stream-warning'), true);
    setHidden(element('stream-statistics'), true);
    setHidden(element('stream-transient'), true);
    setHidden(element('stream-fatal'), true);
    var warning = element('stream-warning');
    var statistics = element('stream-statistics');
    var transient = element('stream-transient');
    if (warning) warning.textContent = '';
    if (statistics) statistics.textContent = '';
    if (transient) transient.textContent = '';
    if (transientTimer !== null) {
      root.clearTimeout(transientTimer);
      transientTimer = null;
    }
  }

  function setInputMode(mode) {
    return root.MoonlightInput ? root.MoonlightInput.setMode(mode) : mode;
  }

  function setStreamSurface(state) {
    if (state === true) state = 'active';
    if (state === false || state == null) state = 'inactive';
    if (['inactive', 'loading', 'active', 'stopping', 'error'].indexOf(state) === -1) {
      throw nativeError('Unknown stream surface state: ' + state, 'invalid-surface-state');
    }
    root.document.documentElement.dataset.streamState = state;
    var loading = element('stream-loading');
    setHidden(loading, state !== 'loading' && state !== 'stopping');
    if (state === 'stopping') {
      var progress = element('stream-progress');
      if (progress) progress.textContent = 'Stopping stream…';
    }
    setInputMode(state === 'loading' || state === 'active' || state === 'stopping' ? 'stream' : 'ui');
    var video = element('wasm_module');
    if (state === 'active' && video) {
      try { video.focus(); } catch (_) {}
    } else if (state === 'inactive') {
      clearStreamOverlays();
      if (video) {
        try { video.blur(); } catch (_) {}
      }
    }
    return state;
  }

  function showProgress(message) {
    var progress = element('stream-progress');
    if (progress) progress.textContent = message || 'Starting stream…';
    setHidden(element('stream-loading'), false);
  }

  function showWarning(message) {
    var warning = element('stream-warning');
    if (warning) warning.textContent = message || '';
    setHidden(warning, !message);
  }

  function showStatistics(message) {
    var statistics = element('stream-statistics');
    if (statistics) statistics.textContent = message || '';
    setHidden(statistics, !message);
  }

  function showTransient(message) {
    var transient = element('stream-transient');
    if (transient) transient.textContent = message || '';
    setHidden(transient, !message);
    if (transientTimer !== null) root.clearTimeout(transientTimer);
    if (message) {
      transientTimer = root.setTimeout(function() {
        setHidden(transient, true);
        transientTimer = null;
      }, 5000);
    }
  }

  function showFatal(message) {
    var fatal = element('stream-fatal');
    var fatalMessage = element('stream-fatal-message');
    if (fatalMessage) fatalMessage.textContent = message || 'The streaming session failed.';
    setHidden(fatal, false);
  }

  function dismissFatal() {
    setHidden(element('stream-fatal'), true);
  }

  function rejectOutstanding(reason) {
    Object.keys(asyncCallbacks).forEach(function(id) {
      asyncCallbacks[id].reject(reason);
      delete asyncCallbacks[id];
    });
    if (pendingStreamStart) {
      root.clearTimeout(pendingStreamStart.timer);
      pendingStreamStart.reject(reason);
      pendingStreamStart = null;
    }
  }

  function finishRuntimeFailure(error) {
    runtimeState = 'failed';
    runtimeReady = false;
    var normalized = error instanceof Error ? error : nativeError(String(error), 'runtime-load-failed');
    rejectOutstanding(normalized);
    if (runtimeReject) runtimeReject(normalized);
    runtimeResolve = null;
    runtimeReject = null;
    emit({ type: 'runtime', state: 'failed', error: normalized.message });
    debug('error', 'runtime failed', { error: normalized.message });
  }

  function finishRuntimeReady() {
    moduleRef = root.Module;
    runtimeReady = true;
    runtimeState = 'ready';
    var result = {
      ready: true,
      bridgeVersion: BRIDGE_VERSION,
      platform: getPlatformInfo()
    };
    if (runtimeResolve) runtimeResolve(result);
    runtimeResolve = null;
    runtimeReject = null;
    emit({ type: 'runtime', state: 'ready', platform: result.platform });
    debug('info', 'runtime ready', { bridgeVersion: BRIDGE_VERSION });
  }

  function initialize() {
    if (runtimeReady) {
      return Promise.resolve({
        ready: true,
        bridgeVersion: BRIDGE_VERSION,
        platform: getPlatformInfo()
      });
    }
    if (runtimePromise) {
      return runtimePromise;
    }
    if (!element('wasm_module')) {
      return Promise.reject(nativeError(
        'The permanent #wasm_module video element is missing.',
        'missing-video-surface'
      ));
    }

    runtimeState = 'loading';
    emit({ type: 'runtime', state: 'loading' });
    runtimePromise = new Promise(function(resolve, reject) {
      runtimeResolve = resolve;
      runtimeReject = reject;

      var runtimeTimer = root.setTimeout(function() {
        if (!runtimeReady) {
          finishRuntimeFailure(nativeError(
            'Timed out waiting for the Moonlight WASM runtime.',
            'runtime-timeout'
          ));
        }
      }, RUNTIME_TIMEOUT_MS);

      var moduleConfig = {
        noExitRuntime: true,
        locateFile: function(path) {
          try {
            return new URL(path, root.document.baseURI).toString();
          } catch (_) {
            return path;
          }
        },
        onRuntimeInitialized: function() {
          root.clearTimeout(runtimeTimer);
          finishRuntimeReady();
        },
        onAbort: function(reason) {
          root.clearTimeout(runtimeTimer);
          finishRuntimeFailure(nativeError(
            'Moonlight WASM aborted: ' + String(reason || 'unknown reason'),
            'runtime-abort'
          ));
        },
        onExit: function(status) {
          emit({ type: 'runtime', state: 'exited', status: Number(status) || 0 });
        }
      };
      moduleRef = moduleConfig;
      root.Module = moduleConfig;

      var existingScript = element(RUNTIME_SCRIPT_ID);
      if (existingScript) {
        return;
      }
      var script = root.document.createElement('script');
      script.id = RUNTIME_SCRIPT_ID;
      script.src = RUNTIME_SCRIPT;
      script.async = true;
      script.onerror = function() {
        root.clearTimeout(runtimeTimer);
        finishRuntimeFailure(nativeError(
          'Unable to load ' + RUNTIME_SCRIPT + '.',
          'runtime-script-load-failed'
        ));
      };
      root.document.body.appendChild(script);
    });
    return runtimePromise;
  }

  function getModuleMethod(name) {
    var module = moduleRef || root.Module;
    if (!runtimeReady || !module || typeof module[name] !== 'function') {
      throw nativeError('Moonlight native method is unavailable: ' + name, 'missing-native-method', {
        method: name,
        runtimeState: runtimeState
      });
    }
    return { module: module, method: module[name] };
  }

  function unwrapMessageResult(result, methodName) {
    if (!result || typeof result.type !== 'string') {
      throw nativeError('Invalid result from native method ' + methodName + '.', 'invalid-native-result');
    }
    if (result.type === 'resolve') {
      return result.ret;
    }
    throw nativeError(String(result.ret || methodName + ' failed.'), 'native-rejected', {
      method: methodName,
      nativeResult: result.ret
    });
  }

  function callMessageResult(methodName, args) {
    return initialize().then(function() {
      var target = getModuleMethod(methodName);
      return unwrapMessageResult(target.method.apply(target.module, args || []), methodName);
    });
  }

  function callRaw(methodName, args) {
    return initialize().then(function() {
      var target = getModuleMethod(methodName);
      return target.method.apply(target.module, args || []);
    });
  }

  function callAsync(methodName, args) {
    return initialize().then(function() {
      var target = getModuleMethod(methodName);
      return new Promise(function(resolve, reject) {
        var id = callbackId++;
        asyncCallbacks[id] = { resolve: resolve, reject: reject, method: methodName };
        try {
          target.method.apply(target.module, [id].concat(args || []));
        } catch (error) {
          delete asyncCallbacks[id];
          reject(error);
        }
      });
    });
  }

  function handlePromiseMessage(id, resultType, response) {
    var pending = asyncCallbacks[id];
    if (!pending) {
      debug('warn', 'orphaned native callback', { callbackId: id, resultType: resultType });
      return;
    }
    delete asyncCallbacks[id];
    if (resultType === 'resolve') {
      pending.resolve(response);
    } else {
      pending.reject(nativeError(String(response || pending.method + ' failed.'), 'native-async-rejected', {
        method: pending.method,
        callbackId: id
      }));
    }
  }

  function parseLifecycle(message) {
    var match = message.match(/^(streamStarting|streamStarted|streamStopping):\s*(\d+)$/);
    if (match) {
      return { name: match[1], attemptId: parseInt(match[2], 10) };
    }
    match = message.match(/^streamStartFailed:\s*(\d+):(-?\d+):(.*)$/);
    if (match) {
      return {
        name: 'streamStartFailed',
        attemptId: parseInt(match[1], 10),
        errorCode: parseInt(match[2], 10),
        reason: match[3] || ''
      };
    }
    match = message.match(/^streamTerminated:\s*(\d+):(-?\d+)$/);
    if (match) {
      return {
        name: 'streamTerminated',
        attemptId: parseInt(match[1], 10),
        errorCode: parseInt(match[2], 10),
        legacy: false
      };
    }
    match = message.match(/^streamTerminated:\s*(-?\d+)$/);
    if (match) {
      return {
        name: 'streamTerminated',
        attemptId: null,
        errorCode: parseInt(match[1], 10),
        legacy: true
      };
    }
    return null;
  }

  function isStaleLifecycle(event) {
    if (!event || event.attemptId == null) return false;
    if (pendingStreamStart && pendingStreamStart.attemptId !== event.attemptId) return true;
    return !pendingStreamStart && activeStreamAttemptId != null &&
      activeStreamAttemptId !== event.attemptId;
  }

  function streamStartError(event, fallback) {
    return nativeError(event.reason || fallback || 'Unable to start stream.', 'stream-start-failed', {
      attemptId: event.attemptId,
      errorCode: event.errorCode,
      lifecycle: event.name
    });
  }

  function settleStreamStart(event, didStart) {
    if (!pendingStreamStart) {
      earlyStreamResult = { event: event, didStart: didStart };
      return;
    }
    if (event.attemptId != null && pendingStreamStart.attemptId !== event.attemptId) {
      return;
    }
    var pending = pendingStreamStart;
    pendingStreamStart = null;
    root.clearTimeout(pending.timer);
    if (didStart) {
      pending.resolve(event);
    } else {
      pending.reject(streamStartError(event));
    }
  }

  function waitForStreamStart(attemptId) {
    if (!Number.isFinite(attemptId) || attemptId <= 0) {
      return Promise.reject(nativeError(
        'Native startStream did not return a valid attempt ID.',
        'invalid-stream-attempt'
      ));
    }
    if (pendingStreamStart) {
      var superseded = pendingStreamStart;
      root.clearTimeout(superseded.timer);
      superseded.reject(nativeError(
        'Stream start was superseded by a newer request.',
        'stream-start-superseded'
      ));
      pendingStreamStart = null;
    }
    if (earlyStreamResult) {
      var early = earlyStreamResult;
      earlyStreamResult = null;
      if (early.event.attemptId === attemptId) {
        return early.didStart
          ? Promise.resolve(early.event)
          : Promise.reject(streamStartError(early.event));
      }
    }
    return new Promise(function(resolve, reject) {
      var timer = root.setTimeout(function() {
        if (pendingStreamStart && pendingStreamStart.attemptId === attemptId) {
          pendingStreamStart = null;
          setStreamSurface('error');
          showFatal('Timed out waiting for the host stream to start.');
          reject(nativeError(
            'Timed out waiting for native streamStarted.',
            'stream-start-timeout',
            { attemptId: attemptId }
          ));
        }
      }, STREAM_START_TIMEOUT_MS);
      pendingStreamStart = {
        attemptId: attemptId,
        timer: timer,
        resolve: resolve,
        reject: reject
      };
    });
  }

  function parseJsonPayload(payload) {
    try {
      return JSON.parse(payload);
    } catch (_) {
      return null;
    }
  }

  function playRumble(index, weakMagnitude, strongMagnitude) {
    var getter = root.navigator && (root.navigator.getGamepads || root.navigator.webkitGetGamepads);
    var gamepads = typeof getter === 'function' ? getter.call(root.navigator) : [];
    var gamepad = gamepads && gamepads[index];
    var actuator = gamepad && (gamepad.vibrationActuator || (gamepad.hapticActuators && gamepad.hapticActuators[0]));
    if (actuator && typeof actuator.playEffect === 'function') {
      actuator.playEffect('dual-rumble', {
        startDelay: 0,
        duration: 5000,
        weakMagnitude: weakMagnitude,
        strongMagnitude: strongMagnitude
      }).catch(function() {});
    } else if (actuator && typeof actuator.pulse === 'function') {
      actuator.pulse(Math.max(weakMagnitude, strongMagnitude), 5000);
    }
  }

  function handleLifecycle(event) {
    if (isStaleLifecycle(event)) {
      emit({
        type: 'lifecycle',
        name: event.name,
        attemptId: event.attemptId,
        stale: true,
        errorCode: event.errorCode,
        reason: event.reason || ''
      });
      return;
    }
    emit({
      type: 'lifecycle',
      name: event.name,
      attemptId: event.attemptId,
      errorCode: event.errorCode,
      reason: event.reason || '',
      legacy: !!event.legacy
    });

    if (event.name === 'streamStarting') {
      setStreamSurface('loading');
      return;
    }
    if (event.name === 'streamStarted') {
      activeStreamAttemptId = event.attemptId;
      settleStreamStart(event, true);
      setHidden(element('stream-loading'), true);
      setStreamSurface('active');
      return;
    }
    if (event.name === 'streamStartFailed') {
      settleStreamStart(event, false);
      if (activeStreamAttemptId === event.attemptId) activeStreamAttemptId = null;
      if (root.MoonlightAudio) root.MoonlightAudio.stop();
      setStreamSurface('error');
      showFatal(event.reason || 'Unable to start the streaming session.');
      return;
    }
    if (event.name === 'streamStopping') {
      setStreamSurface('stopping');
      return;
    }
    if (event.name === 'streamTerminated') {
      settleStreamStart(event, false);
      if (event.attemptId == null || activeStreamAttemptId === event.attemptId) {
        activeStreamAttemptId = null;
      }
      if (root.MoonlightAudio) root.MoonlightAudio.stop();
      if (!event.errorCode) {
        setStreamSurface('inactive');
      } else {
        setStreamSurface('error');
        showFatal('Connection terminated (error ' + event.errorCode + ').');
      }
    }
  }

  function handleNativeMessage(value) {
    var message = typeof value === 'string' ? value :
      (value && typeof value.data === 'string' ? value.data : String(value || ''));
    var lifecycle = parseLifecycle(message);
    if (lifecycle) {
      handleLifecycle(lifecycle);
      return;
    }
    if (message === 'Connection Established') {
      setHidden(element('stream-loading'), true);
      setStreamSurface('active');
      emit({ type: 'lifecycle', name: 'connectionEstablished', attemptId: activeStreamAttemptId });
      return;
    }
    if (message === 'displayVideo') {
      setStreamSurface('active');
      emit({ type: 'lifecycle', name: 'displayVideo', attemptId: activeStreamAttemptId });
      return;
    }

    var separator = message.indexOf(': ');
    var prefix = separator === -1 ? message : message.slice(0, separator);
    var payload = separator === -1 ? '' : message.slice(separator + 2);
    if (prefix === 'ProgressMsg') {
      showProgress(payload);
      emit({ type: 'progress', message: payload });
    } else if (prefix === 'TransientMsg') {
      showTransient(payload);
      emit({ type: 'transient', message: payload });
    } else if (prefix === 'CodecProfileResult') {
      emit({ type: 'codec-profile', payload: payload, data: parseJsonPayload(payload) });
    } else if (prefix === 'DialogMsg') {
      showFatal(payload);
      emit({ type: 'dialog', severity: 'error', message: payload });
    } else if (prefix === 'WarningMsg') {
      showWarning(payload);
      emit({ type: 'warning', visible: true, message: payload });
    } else if (prefix === 'NoWarningMsg') {
      showWarning('');
      emit({ type: 'warning', visible: false, message: payload });
    } else if (prefix === 'StatMsg') {
      showStatistics(payload);
      emit({ type: 'statistics', visible: true, message: payload });
    } else if (prefix === 'NoStatMsg') {
      showStatistics('');
      emit({ type: 'statistics', visible: false, message: payload });
    } else if (prefix === 'controllerRumble') {
      var rumbleValues = payload.split(',');
      var gamepadIndex = parseInt(rumbleValues[0], 10);
      var weak = Number(rumbleValues[1]) || 0;
      var strong = Number(rumbleValues[2]) || 0;
      playRumble(gamepadIndex, weak, strong);
      emit({
        type: 'rumble',
        gamepadIndex: gamepadIndex,
        weakMagnitude: weak,
        strongMagnitude: strong
      });
    } else if (message.indexOf('mouseEmulationOn') === 0) {
      showTransient('Mouse emulation is activated');
      emit({ type: 'mouse-emulation', enabled: true });
    } else if (message.indexOf('mouseEmulationOff') === 0) {
      showTransient('Mouse emulation is deactivated');
      emit({ type: 'mouse-emulation', enabled: false });
    } else {
      emit({ type: 'native-message', message: message });
    }
  }

  function readField(request, names, fallback) {
    for (var index = 0; index < names.length; index += 1) {
      if (request[names[index]] != null) return request[names[index]];
    }
    return fallback;
  }

  function mimeTypesToWire(value) {
    if (Array.isArray(value)) {
      return value.map(function(item) { return String(item); }).filter(Boolean).join('\n');
    }
    return value == null ? '' : String(value);
  }

  function streamRequestToArgs(request) {
    request = request || {};
    return [
      readField(request, ['hostAddress', 'host', 'address'], ''),
      Number(readField(request, ['hostHttpPort', 'httpPort'], 0)),
      String(readField(request, ['width'], '1280')),
      String(readField(request, ['height'], '720')),
      String(readField(request, ['fps', 'frameRate'], '60')),
      String(readField(request, ['bitrate', 'bitrateKbps'], '10000')),
      readField(request, ['rikey', 'remoteInputKey'], ''),
      readField(request, ['rikeyid', 'remoteInputKeyId'], ''),
      readField(request, ['appversion', 'appVersion'], ''),
      readField(request, ['gfeversion', 'gfeVersion'], ''),
      readField(request, ['sessionUrl', 'rtspurl', 'rtspSessionUrl'], ''),
      Number(readField(request, ['serverCodecModeSupport'], 0)),
      !!readField(request, ['framePacing'], false),
      !!readField(request, ['optimizeGameSettings', 'optimizeGames'], false),
      !!readField(request, ['rumbleFeedback'], false),
      !!readField(request, ['mouseEmulation'], false),
      !!readField(request, ['flipAbButtons', 'flipABfaceButtons'], false),
      !!readField(request, ['flipXyButtons', 'flipXYfaceButtons'], false),
      readField(request, ['audioConfiguration', 'audioConfig'], 'Stereo'),
      Number(readField(request, ['audioPacketDurationMs', 'audioPacketDuration'], 0)),
      Number(readField(request, ['audioJitterBufferMs', 'audioJitterMs'], 100)),
      !!readField(request, ['playAudioOnHost', 'playHostAudio'], false),
      readField(request, ['videoCodec'], 'H264'),
      !!readField(request, ['hdr', 'hdrMode'], false),
      !!readField(request, ['fullColorRange', 'fullRange'], false),
      !!readField(request, ['gameMode'], true),
      !!readField(request, ['disableConnectionWarnings', 'disableWarnings'], false),
      !!readField(request, ['showPerformanceStats', 'performanceStats'], false),
      mimeTypesToWire(readField(request, ['disabledCodecMimeTypes', 'disabledVideoMimeTypes'], ''))
    ];
  }

  function codecProbeToArgs(request) {
    request = request || {};
    return [
      String(readField(request, ['width'], '1280')),
      String(readField(request, ['height'], '720')),
      String(readField(request, ['fps', 'frameRate'], '60')),
      !!readField(request, ['hdrMode'], false),
      Number(readField(request, ['serverCodecModeSupport'], 0)),
      readField(request, ['preferredCodec', 'videoCodec'], 'H264'),
      mimeTypesToWire(readField(request, ['disabledMimeTypes', 'disabledCodecMimeTypes', 'disabledVideoMimeTypes'], ''))
    ];
  }

  function makeCertificate() {
    return callMessageResult('makeCert', []);
  }

  function httpInit(cert, privateKey, uniqueId) {
    return callMessageResult('httpInit', [cert, privateKey, uniqueId]);
  }

  function openText(url, pinnedPublicKey) {
    return callAsync('openUrl', [url, pinnedPublicKey == null ? null : pinnedPublicKey, false]);
  }

  function openBinary(url, pinnedPublicKey) {
    return callAsync('openUrl', [url, pinnedPublicKey == null ? null : pinnedPublicKey, true]).then(function(value) {
      if (value instanceof Uint8Array) return value;
      if (value instanceof ArrayBuffer) return new Uint8Array(value);
      return new Uint8Array(value || []);
    });
  }

  function pair(serverMajorVersion, address, httpPort, pin, uniqueId) {
    if (typeof serverMajorVersion === 'object' && serverMajorVersion !== null) {
      var request = serverMajorVersion;
      return pair(
        readField(request, ['serverMajorVersion'], ''),
        readField(request, ['address', 'host'], ''),
        readField(request, ['httpPort'], 0),
        readField(request, ['pin', 'randomNumber'], ''),
        readField(request, ['uniqueId'], '')
      );
    }
    return callAsync('pair', [String(serverMajorVersion), address, Number(httpPort), String(pin), uniqueId || '']);
  }

  // The C++ embind export is lowercase `stun`; the legacy JS used `STUN` by mistake.
  function stun() {
    return callAsync('stun', []);
  }

  function wakeOnLan(macAddress) {
    // WakeOnLan currently accepts a callback ID in C++ but never posts a
    // callback. Dispatch it with ID 0 and resolve once native accepted it.
    return callRaw('wakeOnLan', [0, macAddress]).then(function() { return true; });
  }

  function unlockAudio() {
    return root.MoonlightAudio ? root.MoonlightAudio.unlock() : false;
  }

  function startStream(request) {
    dismissFatal();
    showWarning('');
    showStatistics('');
    showProgress('Starting stream…');
    setStreamSurface('loading');
    if (root.MoonlightAudio) {
      root.MoonlightAudio.start(Number(readField(
        request || {},
        ['audioJitterBufferMs', 'audioJitterMs'],
        100
      )));
    }
    var args = streamRequestToArgs(request);
    return callMessageResult('startStream', args).then(function(value) {
      var attemptId = parseInt(value, 10);
      return waitForStreamStart(attemptId);
    }).catch(function(error) {
      if (root.MoonlightAudio) root.MoonlightAudio.stop();
      if (!pendingStreamStart) {
        setStreamSurface('error');
        showFatal(error && error.message ? error.message : String(error));
      }
      throw error;
    });
  }

  function stopStream() {
    setStreamSurface('stopping');
    return callMessageResult('stopStream', []).catch(function(error) {
      setStreamSurface(activeStreamAttemptId == null ? 'inactive' : 'active');
      throw error;
    });
  }

  function toggleStats() {
    return callRaw('toggleStats', []).then(function() { return true; });
  }

  function probeVideoCodecSupport(request) {
    return callRaw('probeVideoCodecSupport', codecProbeToArgs(request)).then(function(value) {
      if (typeof value !== 'string') return value;
      return parseJsonPayload(value) || { raw: value };
    });
  }

  function startLogExportServer(payload, filename, token, requestedPort) {
    return callMessageResult('startLogExportServer', [
      payload,
      filename,
      token,
      Number(requestedPort) || 0
    ]);
  }

  function stopLogExportServer() {
    return callMessageResult('stopLogExportServer', []);
  }

  function sendEscape() {
    try {
      var target = getModuleMethod('sendKeyboardEvent');
      target.method.call(target.module, (0x80 << 8) | 0x1b, 0x03, 0);
      target.method.call(target.module, (0x80 << 8) | 0x1b, 0x04, 0);
      return true;
    } catch (_) {
      return false;
    }
  }

  function setEventSink(sink) {
    eventSink = typeof sink === 'function' ? sink : null;
  }

  function getPlatformInfo() {
    return root.MoonlightTizenPlatform
      ? root.MoonlightTizenPlatform.getPlatformInfo()
      : { isTizen: false, supportsNativeStreaming: false };
  }

  function connectedGamepadMask() {
    return root.MoonlightInput ? root.MoonlightInput.connectedGamepadMask() : 0;
  }

  // Names referenced directly by EM_ASM in the existing C++ runtime.
  root.handleMessage = handleNativeMessage;
  root.handlePromiseMessage = handlePromiseMessage;

  var facade = {
    bridgeVersion: BRIDGE_VERSION,
    initialize: initialize,
    isAvailable: function() { return !!getPlatformInfo().supportsNativeStreaming; },
    isReady: function() { return runtimeReady; },
    getRuntimeState: function() { return runtimeState; },
    makeCertificate: makeCertificate,
    makeCert: makeCertificate,
    httpInit: httpInit,
    openText: openText,
    openBinary: openBinary,
    pair: pair,
    stun: stun,
    wakeOnLan: wakeOnLan,
    startStream: startStream,
    stopStream: stopStream,
    toggleStats: toggleStats,
    probeVideoCodecSupport: probeVideoCodecSupport,
    startLogExportServer: startLogExportServer,
    stopLogExportServer: stopLogExportServer,
    sendEscape: sendEscape,
    setDiagnosticLogLevel: function(level) {
      return root.MoonlightLogger ? root.MoonlightLogger.setLevel(level) : 'off';
    },
    logDiagnostic: function(level, eventName, details) {
      if (!root.MoonlightLogger) return false;
      root.MoonlightLogger.log(level || 'info', [eventName || 'dart.event'], {
        source: 'dart',
        event: eventName || 'dart.event',
        details: details || {}
      });
      return true;
    },
    getDiagnosticLogStatus: function() {
      if (!root.MoonlightLogger) {
        return { level: 'off', entryCount: 0, bytes: 0, available: false };
      }
      var status = root.MoonlightLogger.getStatusSync();
      return Object.assign({}, status, {
        entryCount: status.recentEntries || 0,
        bytes: status.sizeBytes || 0
      });
    },
    getDiagnosticLogs: function() {
      return root.MoonlightLogger
        ? root.MoonlightLogger.getExportText()
        : Promise.resolve('');
    },
    clearDiagnosticLogs: function() {
      if (!root.MoonlightLogger) {
        return Promise.resolve({ level: 'off', entryCount: 0, bytes: 0, available: false });
      }
      return root.MoonlightLogger.clear().then(function() {
        return root.MoonlightLogger.getStatusSync();
      });
    },
    getDiagnosticQrSvg: function(value) {
      return root.MoonlightLogger ? root.MoonlightLogger.makeQrSvg(value) : '';
    },
    getIpAddress: function() {
      return root.MoonlightTizenPlatform ? root.MoonlightTizenPlatform.getIpAddress() : '';
    },
    unlockAudio: unlockAudio,
    setStreamSurface: setStreamSurface,
    dismissFatal: dismissFatal,
    setInputMode: setInputMode,
    registerInputSink: function(sink) {
      if (root.MoonlightInput) root.MoonlightInput.setSink(sink);
    },
    connectedGamepadMask: connectedGamepadMask,
    getConnectedGamepadMask: connectedGamepadMask,
    setEventSink: setEventSink,
    getPlatformInfo: getPlatformInfo,
    registerKeys: function(keys) {
      return root.MoonlightTizenPlatform
        ? root.MoonlightTizenPlatform.registerKeys(keys)
        : { available: false, registered: [], failed: [] };
    },
    setVolume: function(action) {
      return root.MoonlightTizenPlatform && root.MoonlightTizenPlatform.setVolume(action);
    },
    restartApp: function() {
      return root.MoonlightTizenPlatform
        ? root.MoonlightTizenPlatform.restartApp()
        : (root.location.reload(), true);
    },
    exitApp: function() {
      return root.MoonlightTizenPlatform && root.MoonlightTizenPlatform.exitApp();
    },
    __testing: Object.freeze({
      parseLifecycle: parseLifecycle,
      streamRequestToArgs: streamRequestToArgs,
      codecProbeToArgs: codecProbeToArgs,
      handleNativeMessage: handleNativeMessage,
      useReadyModule: function(module) {
        moduleRef = module;
        root.Module = module;
        runtimeReady = true;
        runtimeState = 'ready';
        runtimePromise = Promise.resolve({ ready: true, bridgeVersion: BRIDGE_VERSION });
      },
      resetStreamState: function() {
        if (pendingStreamStart) root.clearTimeout(pendingStreamStart.timer);
        pendingStreamStart = null;
        activeStreamAttemptId = null;
        earlyStreamResult = null;
      }
    })
  };

  root.MoonlightNative = Object.freeze(facade);
})(window);
