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

function logWasmMessage(level, eventName, details) {
  if (typeof window.moonlightDebugLog !== 'function') {
    return;
  }
  window.moonlightDebugLog(level, eventName, Object.assign({
    source: 'messages.js'
  }, details || {}));
}

function classifyWasmMessage(msg) {
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
    default:
      return 'UNKNOWN';
  }
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
          resolve(ret.ret);
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
  // If it's a recognized event, notify the appropriate function
  if (msg.indexOf('streamTerminated: ') === 0) {
    if (typeof stopAudioScheduler === 'function') {
      stopAudioScheduler();
    }
    // Remove the on-screen overlays
    $('#connection-warnings, #performance-stats').css('display', 'none');
    // Remove the video stream now
    $('#listener').removeClass('fullscreen');
    $('#loadingSpinner').css('display', 'none');
    $('body').css('backgroundColor', '#282C38');
    $('#wasm_module').css('display', 'none');
    // Show a termination snackbar message if the termination was unexpected
    var errorCode = parseInt(msg.replace('streamTerminated: ', ''));
    logWasmMessage(errorCode === 0 ? 'info' : 'error', 'stream terminated', {
      errorCode: errorCode,
      reason: describeStreamTermination(errorCode),
      isInGame: typeof isInGame !== 'undefined' ? isInGame : null
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
    // Return to the app list with new current game
    showApps(api);
    setTimeout(() => {
      // Scroll to the current game row
      Navigation.switch();
      // Switch to Apps view
      Navigation.change(Views.Apps);
    }, 1500);
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
