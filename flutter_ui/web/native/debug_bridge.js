(function() {
  'use strict';

  var config = window.MOONLIGHT_DEBUG_BRIDGE || {};
  var logger = window.MoonlightLogger;

  function loggerStatus() {
    return logger && typeof logger.getStatusSync === 'function' ? logger.getStatusSync() : null;
  }

  function runtimeInfo() {
    try {
      return window.MoonlightNative && typeof window.MoonlightNative.runtimeInfo === 'function'
        ? window.MoonlightNative.runtimeInfo()
        : null;
    } catch (error) {
      return { error: describeError(error) };
    }
  }

  function getState() {
    return {
      href: window.location.origin + window.location.pathname,
      readyState: document.readyState,
      title: document.title,
      visibilityState: document.visibilityState,
      online: navigator.onLine,
      logger: loggerStatus(),
      runtime: runtimeInfo(),
      capabilities: {
        tizen: typeof window.tizen !== 'undefined',
        flutter: !!document.querySelector('flutter-view'),
        nativeBridge: !!window.MoonlightNative,
        wasm: typeof WebAssembly !== 'undefined',
        sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
        gamepads: !!navigator.getGamepads
      }
    };
  }

  var disabledApi = {
    enabled: false,
    log: function() {},
    flush: function() { return Promise.resolve(); },
    getState: getState,
    executeCommand: function() {
      return Promise.reject(new Error('Moonlight debug bridge is disabled'));
    }
  };

  if (!config.enabled || !config.serverUrl || !config.token || !window.fetch) {
    window.MoonlightDebugBridge = disabledApi;
    return;
  }

  var serverUrl = String(config.serverUrl).replace(/\/+$/, '');
  var token = String(config.token);
  var clientName = String(config.clientName || 'moonlight-flutter');
  var clientId = getClientId();
  var basePollMs = positiveNumber(config.pollMs, 1000);
  var currentPollMs = basePollMs;
  var maxPollMs = positiveNumber(config.maxPollMs, 8000);
  var flushDelayMs = positiveNumber(config.flushMs, 500);
  var maxQueueSize = positiveNumber(config.maxQueueSize, 500);
  var queue = [];
  var flushTimer = null;
  var flushing = false;

  function positiveNumber(value, fallback) {
    var number = Number(value);
    return isFinite(number) && number > 0 ? number : fallback;
  }

  function getClientId() {
    var key = 'moonlightFlutterDebugBridgeClientId';
    try {
      var existing = window.localStorage && window.localStorage.getItem(key);
      if (existing) {
        return existing;
      }
      var created = 'flutter-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
      window.localStorage.setItem(key, created);
      return created;
    } catch (error) {
      return 'flutter-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
    }
  }

  function describeError(error) {
    return {
      name: error && error.name ? String(error.name) : 'Error',
      message: error && error.message ? String(error.message).slice(0, 4000) : String(error || ''),
      stack: error && error.stack ? String(error.stack).slice(0, 12000) : ''
    };
  }

  function redact(value) {
    return logger && typeof logger.redactValue === 'function' ? logger.redactValue(value) : value;
  }

  function requestJson(method, path, body) {
    return window.fetch(serverUrl + path, {
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'X-Debug-Token': token
      },
      body: body == null ? null : JSON.stringify(redact(body))
    }).then(function(response) {
      return response.text().then(function(text) {
        var result = text ? JSON.parse(text) : {};
        if (!response.ok) {
          throw new Error(result.error || ('HTTP ' + response.status));
        }
        return result;
      });
    });
  }

  function scheduleFlush(delayMs) {
    if (flushTimer !== null) {
      return;
    }
    flushTimer = window.setTimeout(function() {
      flushTimer = null;
      flush();
    }, delayMs == null ? flushDelayMs : delayMs);
  }

  function enqueue(entry) {
    if (!entry) {
      return;
    }
    queue.push(redact(entry));
    if (queue.length > maxQueueSize) {
      queue.splice(0, queue.length - maxQueueSize);
    }
    scheduleFlush();
  }

  function flush() {
    if (flushing || queue.length === 0) {
      return Promise.resolve();
    }
    flushing = true;
    var entries = queue.splice(0, 100);
    return requestJson('POST', '/api/logs', {
      clientId: clientId,
      clientName: clientName,
      entries: entries
    }).then(function() {
      flushDelayMs = positiveNumber(config.flushMs, 500);
    }, function() {
      queue = entries.concat(queue).slice(-maxQueueSize);
      flushDelayMs = Math.min(flushDelayMs * 2, 5000);
    }).then(function() {
      flushing = false;
      if (queue.length > 0) {
        scheduleFlush(flushDelayMs);
      }
    });
  }

  function executeCommand(command) {
    var type = command && command.type;
    var args = command && command.args || {};
    if (type === 'getState') {
      return Promise.resolve(getState());
    }
    if (type === 'getDiagnostics') {
      if (!logger || typeof logger.getExportText !== 'function') {
        throw new Error('Diagnostic logger is unavailable');
      }
      return logger.getExportText().then(function(text) {
        var limit = 750000;
        var logs = text.length > limit ? '[remote export truncated to newest entries]\n' + text.slice(-limit) : text;
        return { status: loggerStatus(), logs: logs, truncated: text.length > limit };
      });
    }
    if (type === 'setLogLevel') {
      if (!logger || typeof logger.setLevel !== 'function') {
        throw new Error('Diagnostic logger is unavailable');
      }
      return Promise.resolve({ level: logger.setLevel(args.level) });
    }
    if (type === 'clearDiagnostics') {
      if (!logger || typeof logger.clear !== 'function') {
        throw new Error('Diagnostic logger is unavailable');
      }
      return logger.clear().then(function(cleared) { return { cleared: cleared }; });
    }
    if (type === 'reload') {
      window.setTimeout(function() { window.location.reload(); }, Math.max(0, Number(args.delayMs) || 0));
      return Promise.resolve({ scheduled: true });
    }
    throw new Error('Unsupported command type: ' + type);
  }

  function sendCommandResult(command, ok, result, error) {
    return requestJson('POST', '/api/commands/' + encodeURIComponent(command.id) + '/result', {
      clientId: clientId,
      commandId: command.id,
      ok: ok,
      result: result || {},
      error: error ? describeError(error) : null
    });
  }

  function runCommand(command) {
    return Promise.resolve().then(function() {
      return executeCommand(command);
    }).then(function(result) {
      return sendCommandResult(command, true, result, null);
    }, function(error) {
      return sendCommandResult(command, false, {}, error);
    });
  }

  function pollCommands() {
    requestJson('GET', '/api/commands?clientId=' + encodeURIComponent(clientId)).then(function(response) {
      currentPollMs = basePollMs;
      var chain = Promise.resolve();
      (response.commands || []).forEach(function(command) {
        chain = chain.then(function() { return runCommand(command); });
      });
      return chain;
    }, function() {
      currentPollMs = Math.min(maxPollMs, Math.max(basePollMs, Math.round(currentPollMs * 1.5)));
    }).then(function() {
      window.setTimeout(pollCommands, currentPollMs);
    });
  }

  if (logger && typeof logger.addSink === 'function') {
    logger.addSink(enqueue);
  }

  window.MoonlightDebugBridge = {
    enabled: true,
    clientId: clientId,
    clientName: clientName,
    log: function(level, message, details) {
      enqueue({
        time: new Date().toISOString(),
        level: level || 'info',
        message: String(message || ''),
        args: [message || ''],
        meta: details || { source: 'manual' }
      });
    },
    flush: flush,
    getState: getState,
    executeCommand: executeCommand
  };

  enqueue({
    time: new Date().toISOString(),
    level: 'info',
    message: 'Flutter remote debug bridge enabled',
    args: ['Flutter remote debug bridge enabled'],
    meta: { source: 'debug-bridge', clientName: clientName }
  });
  scheduleFlush(0);
  window.setTimeout(pollCommands, basePollMs);
})();
