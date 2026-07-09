/* eslint-disable */

const SyncFunctions = {
  // no parameters
  'makeCert': (...args) => Module.makeCert(...args),
  // cert, privateKey, myUniqueid
  'httpInit': (...args) => Module.httpInit(...args),
  /* host, httpPort, width, height, fps, bitrate, rikey, rikeyid, appversion, gfeversion, rtspurl, serverCodecModeSupport,
  framePacing, optimizeGames, rumbleFeedback, mouseEmulation, flipABfaceButtons, flipXYfaceButtons, audioConfig,
  audioPacketDuration, audioJitterMs, playHostAudio, videoCodec, hdrMode, fullRange, gameMode, disableWarnings, performanceStats */
  'startRequest': (...args) => Module.startStream(...args),
  // no parameters
  'stopRequest': (...args) => Module.stopStream(...args),
  // no parameters
  'toggleStats': (...args) => Module.toggleStats(...args),
  // payload, filename, token, requestedPort
  'startLogExportServer': (...args) => Module.startLogExportServer(...args),
  // no parameters
  'stopLogExportServer': (...args) => Module.stopLogExportServer(...args),
};

const AsyncFunctions = {
  // url, ppk, binaryResponse
  'openUrl': (...args) => Module.openUrl(...args),
  // no parameters
  'STUN': (...args) => Module.STUN(...args),
  // serverMajorVersion, address, httpPort, randomNumber
  'pair': (...args) => Module.pair(...args),
  // macAddress
  'wakeOnLan': (...args) => Module.wakeOnLan(...args),
};

var callbacks = {}
var callbacks_ids = 1;
var pendingStreamStart = null;
var activeStreamAttemptId = null;
var lastSettledStreamStartEvent = null;
var STREAM_START_TIMEOUT_MS = 60000;

function logWasmMessage(level, eventName, details) {
  if (typeof window.moonlightDebugLog !== 'function') {
    return;
  }
  window.moonlightDebugLog(level, eventName, Object.assign({
    source: 'messages.js'
  }, details || {}));
}

function classifyWasmMessage(msg) {
  if (msg.indexOf('streamStarting: ') === 0) {
    return 'streamStarting';
  }
  if (msg.indexOf('streamStarted: ') === 0) {
    return 'streamStarted';
  }
  if (msg.indexOf('streamStartFailed: ') === 0) {
    return 'streamStartFailed';
  }
  if (msg.indexOf('streamStopping: ') === 0) {
    return 'streamStopping';
  }
  if (msg.indexOf('streamTerminated: ') === 0) {
    return 'streamTerminated';
  }
  if (msg.indexOf('ProgressMsg: ') === 0) {
    return 'ProgressMsg';
  }
  if (msg.indexOf('TransientMsg: ') === 0) {
    return 'TransientMsg';
  }
  if (msg.indexOf('DialogMsg: ') === 0) {
    return 'DialogMsg';
  }
  if (msg.indexOf('NoWarningMsg: ') === 0) {
    return 'NoWarningMsg';
  }
  if (msg.indexOf('WarningMsg: ') === 0) {
    return 'WarningMsg';
  }
  if (msg.indexOf('NoStatMsg: ') === 0) {
    return 'NoStatMsg';
  }
  if (msg.indexOf('StatMsg: ') === 0) {
    return 'StatMsg';
  }
  if (msg.indexOf('controllerRumble: ') === 0) {
    return 'controllerRumble';
  }
  if (msg.indexOf('mouseEmulationOn') === 0) {
    return 'mouseEmulationOn';
  }
  if (msg.indexOf('mouseEmulationOff') === 0) {
    return 'mouseEmulationOff';
  }
  return 'Other';
}

function sanitizeWasmMessage(msg) {
  if (msg.indexOf('Setting the Remote input key to: ') === 0) {
    return 'Setting the Remote input key to: [redacted]';
  }
  if (msg.indexOf('Setting the Remote input key ID to: ') === 0) {
    return 'Setting the Remote input key ID to: [redacted]';
  }
  if (msg.indexOf('Setting the RTSP session URL to: ') === 0) {
    return 'Setting the RTSP session URL to: [redacted]';
  }
  return msg;
}

function describeStreamTermination(errorCode) {
  switch (errorCode) {
    case 0:
      return 'ML_ERROR_GRACEFUL_TERMINATION';
    case -100:
      return 'ML_ERROR_NO_VIDEO_TRAFFIC';
    case -101:
      return 'ML_ERROR_NO_VIDEO_FRAME';
    case -102:
      return 'ML_ERROR_UNEXPECTED_EARLY_TERMINATION';
    case -103:
      return 'ML_ERROR_PROTECTED_CONTENT';
    case -104:
      return 'ML_ERROR_FRAME_CONVERSION';
    case -200:
      return 'ML_ERROR_WASM_START_FAILED';
    case -201:
      return 'ML_ERROR_WASM_STOP_FAILED';
    default:
      return 'UNKNOWN';
  }
}

function parseStreamLifecycleMessage(msg) {
  var match = msg.match(/^(streamStarting|streamStarted|streamStopping):\s*(\d+)$/);
  if (match) {
    return {
      type: match[1],
      attemptId: parseInt(match[2], 10)
    };
  }

  match = msg.match(/^streamStartFailed:\s*(\d+):(-?\d+):(.*)$/);
  if (match) {
    return {
      type: 'streamStartFailed',
      attemptId: parseInt(match[1], 10),
      errorCode: parseInt(match[2], 10),
      reason: match[3] || ''
    };
  }

  match = msg.match(/^streamTerminated:\s*(\d+):(-?\d+)$/);
  if (match) {
    return {
      type: 'streamTerminated',
      attemptId: parseInt(match[1], 10),
      errorCode: parseInt(match[2], 10),
      legacy: false
    };
  }

  match = msg.match(/^streamTerminated:\s*(-?\d+)$/);
  if (match) {
    return {
      type: 'streamTerminated',
      attemptId: null,
      errorCode: parseInt(match[1], 10),
      legacy: true
    };
  }

  return null;
}

function clearPendingStreamStartTimer() {
  if (pendingStreamStart && pendingStreamStart.timer) {
    clearTimeout(pendingStreamStart.timer);
    pendingStreamStart.timer = null;
  }
}

function createStreamStartError(event, fallbackReason) {
  var reason = event && event.reason ? event.reason : fallbackReason;
  var error = new Error(reason || 'stream start failed');
  if (event) {
    error.attemptId = event.attemptId;
    error.errorCode = event.errorCode;
    error.reason = event.reason;
    error.lifecycleType = event.type;
  }
  return error;
}

function waitForNativeStreamStart(attemptId, summary, startedAt) {
  if (!attemptId || isNaN(attemptId)) {
    return Promise.reject(createStreamStartError({
      type: 'streamStartFailed',
      attemptId: attemptId,
      errorCode: -200,
      reason: 'native startRequest did not return a valid attempt ID'
    }));
  }

  if (pendingStreamStart) {
    logWasmMessage('warn', 'replacing pending stream start waiter', {
      previousAttemptId: pendingStreamStart.attemptId,
      newAttemptId: attemptId
    });
    clearPendingStreamStartTimer();
    pendingStreamStart.reject(createStreamStartError({
      type: 'streamStartFailed',
      attemptId: pendingStreamStart.attemptId,
      errorCode: -200,
      reason: 'superseded by another stream start request'
    }));
    pendingStreamStart = null;
  }

  if (lastSettledStreamStartEvent) {
    if (lastSettledStreamStartEvent.attemptId === attemptId) {
      var settled = lastSettledStreamStartEvent;
      lastSettledStreamStartEvent = null;
      logWasmMessage(settled.didStart ? 'info' : 'error', 'using early native stream start event', {
        attemptId: attemptId,
        type: settled.event.type,
        errorCode: settled.event.errorCode,
        reason: settled.event.reason,
        elapsedMs: Date.now() - startedAt,
        params: summary
      });
      if (settled.didStart) {
        return Promise.resolve(settled.event);
      }
      return Promise.reject(createStreamStartError(settled.event, 'native stream start failed'));
    }
    logWasmMessage('warn', 'discarding stale early native stream start event', {
      requestedAttemptId: attemptId,
      cachedAttemptId: lastSettledStreamStartEvent.attemptId,
      cachedType: lastSettledStreamStartEvent.event ? lastSettledStreamStartEvent.event.type : null
    });
    lastSettledStreamStartEvent = null;
  }

  return new Promise(function(resolve, reject) {
    pendingStreamStart = {
      attemptId: attemptId,
      startedAt: startedAt,
      params: summary,
      resolve: resolve,
      reject: reject,
      timer: setTimeout(function() {
        if (!pendingStreamStart || pendingStreamStart.attemptId !== attemptId) {
          return;
        }
        logWasmMessage('error', 'stream start wait timed out', {
          attemptId: attemptId,
          elapsedMs: Date.now() - startedAt,
          params: summary
        });
        var error = createStreamStartError({
          type: 'streamStartFailed',
          attemptId: attemptId,
          errorCode: -200,
          reason: 'timed out waiting for native streamStarted'
        });
        pendingStreamStart = null;
        reject(error);
      }, STREAM_START_TIMEOUT_MS)
    };

    logWasmMessage('info', 'waiting for native stream start completion', {
      attemptId: attemptId,
      timeoutMs: STREAM_START_TIMEOUT_MS,
      params: summary
    });
  });
}

function settlePendingStreamStart(event, didStart) {
  if (!pendingStreamStart) {
    if (event.attemptId !== null && activeStreamAttemptId === null) {
      lastSettledStreamStartEvent = {
        attemptId: event.attemptId,
        event: event,
        didStart: didStart
      };
    }
    logWasmMessage(event.type === 'streamStarted' ? 'warn' : 'info', 'stream lifecycle event without pending start waiter', {
      type: event.type,
      attemptId: event.attemptId,
      errorCode: event.errorCode,
      reason: event.reason
    });
    return;
  }

  if (event.attemptId !== null && pendingStreamStart.attemptId !== event.attemptId) {
    logWasmMessage('warn', 'ignoring stale stream lifecycle event for pending start', {
      pendingAttemptId: pendingStreamStart.attemptId,
      eventAttemptId: event.attemptId,
      type: event.type,
      errorCode: event.errorCode,
      reason: event.reason
    });
    return;
  }

  var pending = pendingStreamStart;
  clearPendingStreamStartTimer();
  pendingStreamStart = null;

  logWasmMessage(didStart ? 'info' : 'error', didStart ? 'native stream start completed' : 'native stream start failed', {
    attemptId: event.attemptId,
    type: event.type,
    errorCode: event.errorCode,
    reason: event.reason,
    elapsedMs: Date.now() - pending.startedAt,
    params: pending.params
  });

  if (didStart) {
    pending.resolve(event);
  } else {
    pending.reject(createStreamStartError(event, 'native stream start failed'));
  }
}

function isStaleStreamLifecycleEvent(event) {
  if (!event || event.attemptId === null) {
    return false;
  }

  if (pendingStreamStart && pendingStreamStart.attemptId !== event.attemptId) {
    return true;
  }

  if (!pendingStreamStart && activeStreamAttemptId !== null && activeStreamAttemptId !== event.attemptId) {
    return true;
  }

  return false;
}

function summarizeMessageParams(method, params) {
  var values = Array.isArray(params) ? params : [];
  if (method === 'startRequest') {
    return {
      host: values[0],
      httpPort: values[1],
      width: values[2],
      height: values[3],
      fps: values[4],
      bitrateKbps: values[5],
      hasRemoteInputKey: !!values[6],
      hasRemoteInputKeyId: values[7] != null,
      appVersion: values[8],
      gfeVersion: values[9],
      hasRtspSessionUrl: !!values[10],
      rtspSessionUrlLength: values[10] ? String(values[10]).length : 0,
      serverCodecModeSupport: values[11],
      framePacing: values[12],
      optimizeGames: values[13],
      rumbleFeedback: values[14],
      mouseEmulation: values[15],
      flipABfaceButtons: values[16],
      flipXYfaceButtons: values[17],
      audioConfig: values[18],
      audioPacketDuration: values[19],
      audioJitterMs: values[20],
      playHostAudio: values[21],
      videoCodec: values[22],
      hdrMode: values[23],
      fullRange: values[24],
      gameMode: values[25],
      disableWarnings: values[26],
      performanceStats: values[27]
    };
  }
  if (method === 'openUrl') {
    return {
      urlLength: values[0] ? String(values[0]).length : 0,
      hasPrivateKey: !!values[1],
      binaryResponse: values[2]
    };
  }
  if (method === 'httpInit') {
    return {
      hasCert: !!values[0],
      hasPrivateKey: !!values[1],
      hasUniqueId: !!values[2]
    };
  }
  if (method === 'pair') {
    return {
      serverMajorVersion: values[0],
      address: values[1],
      httpPort: values[2],
      hasPin: !!values[3]
    };
  }
  return {
    paramCount: values.length
  };
}

/**
 * var sendMessage - Sends a message with arguments to the Wasm module
 *
 * @param  {String} method A named method
 * @param  {(String|Array)} params An array of options or a single string
 * @return {void}        The Wasm module calls back through the handleMessage method
 */
var sendMessage = function(method, params) {
  var args = Array.isArray(params) ? params : [];
  var summary = summarizeMessageParams(method, args);
  var startedAt = Date.now();
  var lifecycleMethod = method === 'startRequest' || method === 'stopRequest';
  logWasmMessage(lifecycleMethod ? 'info' : 'debug', 'wasm method requested', {
    method: method,
    isSync: !!SyncFunctions[method],
    isAsync: !!AsyncFunctions[method],
    params: summary
  });

  if (SyncFunctions[method]) {
    return new Promise(function(resolve, reject) {
      try {
        const ret = SyncFunctions[method](...args);
        logWasmMessage(ret.type === "resolve" ? (lifecycleMethod ? 'info' : 'debug') : 'error', 'wasm sync method completed', {
          method: method,
          resultType: ret.type,
          elapsedMs: Date.now() - startedAt,
          params: summary
        });
        if (ret.type === "resolve") {
          if (method === 'startRequest') {
            var attemptId = parseInt(ret.ret, 10);
            resolve(waitForNativeStreamStart(attemptId, summary, startedAt));
          } else {
            resolve(ret.ret);
          }
        } else {
          reject(ret.ret);
        }
      } catch (error) {
        logWasmMessage('error', 'wasm sync method threw', {
          method: method,
          elapsedMs: Date.now() - startedAt,
          error: error && error.message ? error.message : String(error),
          params: summary
        });
        reject(error);
      }
    });
  } else if (!AsyncFunctions[method]) {
    logWasmMessage('error', 'wasm method rejected because no bridge function exists', {
      method: method,
      params: summary
    });
    return Promise.reject(new Error('Unknown Wasm bridge method: ' + method));
  } else {
    return new Promise(function(resolve, reject) {
      const id = callbacks_ids++;
      callbacks[id] = {
        'resolve': resolve,
        'reject': reject,
        method: method,
        startedAt: startedAt,
        params: summary
      };

      try {
        AsyncFunctions[method](id, ...args);
        logWasmMessage('debug', 'wasm async method dispatched', {
          method: method,
          callbackId: id,
          params: summary
        });
      } catch (error) {
        delete callbacks[id];
        logWasmMessage('error', 'wasm async method threw during dispatch', {
          method: method,
          callbackId: id,
          elapsedMs: Date.now() - startedAt,
          error: error && error.message ? error.message : String(error),
          params: summary
        });
        reject(error);
      }
    });
  }
}

var handlePromiseMessage = function(callbackId, type, msg) {
  var callback = callbacks[callbackId];
  if (!callback) {
    logWasmMessage('error', 'wasm async callback missing', {
      callbackId: callbackId,
      type: type
    });
    return;
  }

  logWasmMessage(type === 'resolve' ? 'debug' : 'error', 'wasm async method completed', {
    method: callback.method,
    callbackId: callbackId,
    resultType: type,
    elapsedMs: Date.now() - callback.startedAt,
    params: callback.params
  });

  if (typeof callback[type] !== 'function') {
    logWasmMessage('error', 'wasm async callback type invalid', {
      method: callback.method,
      callbackId: callbackId,
      type: type
    });
    delete callbacks[callbackId];
    return;
  }

  callback[type](msg);
  delete callbacks[callbackId];
}

/**
 * handleMessage - Handles messages from the Wasm module
 *
 * @param  {Object} msg An object given by the Wasm module
 * @return {void}
 */
function handleMessage(msg) {
  var safeMessage = sanitizeWasmMessage(msg);
  console.log('%c[messages.js, handleMessage]', 'color: gray;', 'Message data: ', safeMessage);
  var messageType = classifyWasmMessage(msg);
  if (messageType !== 'StatMsg') {
    logWasmMessage('info', 'wasm message received', {
      type: messageType,
      message: safeMessage
    });
  }
  var lifecycleEvent = parseStreamLifecycleMessage(msg);

  // If it's a recognized event, notify the appropriate function
  if (lifecycleEvent && lifecycleEvent.type === 'streamStarting') {
    if (isStaleStreamLifecycleEvent(lifecycleEvent)) {
      logWasmMessage('warn', 'ignoring stale stream starting event', {
        activeAttemptId: activeStreamAttemptId,
        pendingAttemptId: pendingStreamStart ? pendingStreamStart.attemptId : null,
        eventAttemptId: lifecycleEvent.attemptId
      });
      return;
    }
    logWasmMessage('info', 'stream starting', {
      attemptId: lifecycleEvent.attemptId
    });
  } else if (lifecycleEvent && lifecycleEvent.type === 'streamStarted') {
    if (isStaleStreamLifecycleEvent(lifecycleEvent)) {
      logWasmMessage('warn', 'ignoring stale stream started event', {
        activeAttemptId: activeStreamAttemptId,
        pendingAttemptId: pendingStreamStart ? pendingStreamStart.attemptId : null,
        eventAttemptId: lifecycleEvent.attemptId
      });
      return;
    }
    settlePendingStreamStart(lifecycleEvent, true);
    activeStreamAttemptId = lifecycleEvent.attemptId;
    logWasmMessage('info', 'stream connection established', {
      attemptId: lifecycleEvent.attemptId
    });
    // Prepare the screen for video stream
    $('#loadingSpinner').css('display', 'none');
    $('body').css('backgroundColor', 'transparent');
    $('#wasm_module').css('display', '');
    $('#wasm_module').focus();
  } else if (lifecycleEvent && lifecycleEvent.type === 'streamStartFailed') {
    if (isStaleStreamLifecycleEvent(lifecycleEvent)) {
      logWasmMessage('warn', 'ignoring stale stream start failed event', {
        activeAttemptId: activeStreamAttemptId,
        pendingAttemptId: pendingStreamStart ? pendingStreamStart.attemptId : null,
        eventAttemptId: lifecycleEvent.attemptId,
        errorCode: lifecycleEvent.errorCode,
        reason: lifecycleEvent.reason
      });
      return;
    }
    settlePendingStreamStart(lifecycleEvent, false);
    if (activeStreamAttemptId === lifecycleEvent.attemptId) {
      activeStreamAttemptId = null;
    }
    logWasmMessage('error', 'stream start failed', {
      attemptId: lifecycleEvent.attemptId,
      errorCode: lifecycleEvent.errorCode,
      reason: lifecycleEvent.reason
    });
    snackbarLogLong('Unable to start stream: ' + (lifecycleEvent.reason || describeStreamTermination(lifecycleEvent.errorCode)));
    if (typeof resetStreamUiState === 'function') {
      resetStreamUiState('stream start failed: ' + (lifecycleEvent.reason || lifecycleEvent.errorCode), api, { navigateToApps: true });
    }
  } else if (lifecycleEvent && lifecycleEvent.type === 'streamStopping') {
    if (isStaleStreamLifecycleEvent(lifecycleEvent)) {
      logWasmMessage('warn', 'ignoring stale stream stopping event', {
        activeAttemptId: activeStreamAttemptId,
        pendingAttemptId: pendingStreamStart ? pendingStreamStart.attemptId : null,
        eventAttemptId: lifecycleEvent.attemptId
      });
      return;
    }
    logWasmMessage('info', 'stream stopping', {
      attemptId: lifecycleEvent.attemptId
    });
  } else if (lifecycleEvent && lifecycleEvent.type === 'streamTerminated') {
    if (isStaleStreamLifecycleEvent(lifecycleEvent)) {
      logWasmMessage('warn', 'ignoring stale stream terminated event', {
        activeAttemptId: activeStreamAttemptId,
        pendingAttemptId: pendingStreamStart ? pendingStreamStart.attemptId : null,
        eventAttemptId: lifecycleEvent.attemptId,
        errorCode: lifecycleEvent.errorCode
      });
      return;
    }
    // Show a termination snackbar message if the termination was unexpected
    var errorCode = lifecycleEvent.errorCode;
    settlePendingStreamStart(lifecycleEvent, false);
    if (lifecycleEvent.attemptId === null || activeStreamAttemptId === lifecycleEvent.attemptId) {
      activeStreamAttemptId = null;
    }
    logWasmMessage(errorCode === 0 ? 'info' : 'error', 'stream terminated', {
      attemptId: lifecycleEvent.attemptId,
      errorCode: errorCode,
      reason: describeStreamTermination(errorCode),
      isInGame: typeof isInGame !== 'undefined' ? isInGame : null,
      legacyFormat: !!lifecycleEvent.legacy
    });
    switch (errorCode) {
      case 0: // ML_ERROR_GRACEFUL_TERMINATION
        break;
      case -100: // ML_ERROR_NO_VIDEO_TRAFFIC
        snackbarLogLong('No video received from host. Check the host PC\'s firewall and port forwarding rules.');
        break;
      case -101: // ML_ERROR_NO_VIDEO_FRAME
        snackbarLogLong('Your network connection isn\'t performing well. Reduce your video bitrate setting or try a faster connection.');
        break;
      case -102: // ML_ERROR_UNEXPECTED_EARLY_TERMINATION
        snackbarLogLong('Something went wrong on your host PC when starting the stream. Restart your host PC and try again.');
        break;
      case -103: // ML_ERROR_PROTECTED_CONTENT
        snackbarLogLong('An issue occurred on your host PC while starting the stream. Make sure you don\'t have any DRM-protected content open on your host PC.');
        break;
      case -104: // ML_ERROR_FRAME_CONVERSION
        snackbarLogLong('The host PC reported a fatal video encoding error. Try disabling HDR mode, changing the streaming resolution, or changing your host PC\'s display resolution.');
        break;
      default:
        snackbarLogLong('Connection terminated');
        break;
    }
    if (typeof resetStreamUiState === 'function') {
      resetStreamUiState('stream terminated: ' + describeStreamTermination(errorCode), api, { navigateToApps: true });
    } else {
      if (typeof stopAudioScheduler === 'function') {
        stopAudioScheduler();
      }
      $('#connection-warnings, #performance-stats').css('display', 'none');
      $('#listener').removeClass('fullscreen');
      $('#loadingSpinner').css('display', 'none');
      $('body').css('backgroundColor', '#282C38');
      $('#wasm_module').css('display', 'none');
      showApps(api, function() {
        Navigation.change(Views.Apps);
        Navigation.focusCurrent();
      });
    }
  } else if (msg === 'Connection Established') {
    logWasmMessage('info', 'stream connection established');
    // Prepare the screen for video stream
    $('#loadingSpinner').css('display', 'none');
    $('body').css('backgroundColor', 'transparent');
    $('#wasm_module').css('display', '');
    $('#wasm_module').focus();
  } else if (msg.indexOf('ProgressMsg: ') === 0) {
    logWasmMessage('info', 'stream progress', {
      progress: msg.replace('ProgressMsg: ', '')
    });
    // Show progress message under loading spinner
    $('#loadingSpinnerMessage').text(msg.replace('ProgressMsg: ', ''));
  } else if (msg.indexOf('TransientMsg: ') === 0) {
    logWasmMessage('warn', 'stream transient message', {
      message: msg.replace('TransientMsg: ', '')
    });
    // Show transient message as notification
    snackbarLogLong(msg.replace('TransientMsg: ', ''));
  } else if (msg.indexOf('DialogMsg: ') === 0) {
    logWasmMessage('error', 'stream dialog message', {
      message: msg.replace('DialogMsg: ', '')
    });
    // Show dialog message using the warning dialog
    warningDialog('Warning', msg.replace('DialogMsg: ', ''));
  } else if (msg === 'displayVideo') {
    logWasmMessage('info', 'stream display video');
    // Show the video stream now
    $('#listener').addClass('fullscreen');
  } else if (msg.indexOf('NoWarningMsg: ') === 0) {
    logWasmMessage('info', 'stream warning cleared', {
      message: msg.replace('NoWarningMsg: ', '')
    });
    // Hide the connection warnings overlay
    $('#connection-warnings').css('background', 'transparent');
    $('#connection-warnings').text('');
  } else if (msg.indexOf('WarningMsg: ') === 0) {
    logWasmMessage('warn', 'stream connection warning', {
      message: msg.replace('WarningMsg: ', '')
    });
    // Show the connection warnings overlay
    $('#connection-warnings').css('background', 'rgba(0, 0, 0, 0.5)');
    $('#connection-warnings').text(msg.replace('WarningMsg: ', ''));
  } else if (msg.indexOf('NoStatMsg: ') === 0) {
    // Toggle the performance stats switch and save the state
    if ($('#performanceStatsSwitch').prop('checked')) {
      $('#performanceStatsBtn')[0].MaterialSwitch.off();
      savePerformanceStats();
      $('#performance-stats').css('display', 'none');
    }
    // Hide the performance statistics overlay
    $('#performance-stats').css('background', 'transparent');
    $('#performance-stats').text('');
  } else if (msg.indexOf('StatMsg: ') === 0) {
    // Toggle the performance stats switch and save the state
    if (!$('#performanceStatsSwitch').prop('checked')) {
      $('#performanceStatsBtn')[0].MaterialSwitch.on();
      savePerformanceStats();
      $('#performance-stats').css('display', 'inline-block');
    }
    // Show the performance statistics overlay
    $('#performance-stats').css('background', 'rgba(0, 0, 0, 0.5)');
    $('#performance-stats').text(msg.replace('StatMsg: ', ''));
  } else if (msg.indexOf('controllerRumble: ') === 0) {
    const eventData = msg.split(' ')[1].split(',');
    const gamepadIdx = parseInt(eventData[0]);
    const weakMagnitude = parseFloat(eventData[1]);
    const strongMagnitude = parseFloat(eventData[2]);
    const gamepads = navigator.getGamepads();
    const gamepad = gamepads[gamepadIdx];
    // Check if the gamepad exists and if it has a vibrationActuator associated with it
    if (gamepad && gamepad.vibrationActuator) {
      console.log('%c[messages.js, handleMessage]', 'color: gray;', 'Playing rumble on gamepad ' + gamepadIdx + ' with weak magnitude ' + weakMagnitude + ' and strong magnitude ' + strongMagnitude + '...');
      gamepad.vibrationActuator.playEffect('dual-rumble', {
        startDelay: 0,
        duration: 5000, // Moonlight should be sending another rumble event when stopping
        weakMagnitude: weakMagnitude,
        strongMagnitude: strongMagnitude,
      });
    } else {
      console.warn('%c[messages.js, handleMessage]', 'color: gray;', 'Warning: Gamepad ' + gamepadIdx + ' does not support the rumble feature!');
    }
  } else if (msg.indexOf('mouseEmulationOn') === 0) {
    // Show mouse emulation enable status as a notification
    snackbarLogLong('Mouse emulation is activated');
  } else if (msg.indexOf('mouseEmulationOff') === 0) {
    // Show mouse emulation disable status as notification
    snackbarLogLong('Mouse emulation is deactivated');
  }
}
