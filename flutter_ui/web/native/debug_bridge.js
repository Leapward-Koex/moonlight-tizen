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
    var audio = window.MoonlightAudio;
    var mediaElement = typeof document.getElementById === 'function'
      ? document.getElementById('wasm_module')
      : null;
    return {
      href: window.location.origin + window.location.pathname,
      readyState: document.readyState,
      title: document.title,
      visibilityState: document.visibilityState,
      online: navigator.onLine,
      logger: loggerStatus(),
      runtime: runtimeInfo(),
      audio: audio ? {
        context: typeof audio.getContextSnapshot === 'function' ? audio.getContextSnapshot() : null,
        stats: typeof audio.getStats === 'function' ? audio.getStats() : null,
        videoCurrentTime: mediaElement && typeof mediaElement.currentTime === 'number'
          ? mediaElement.currentTime
          : null
      } : null,
      capabilities: {
        tizen: typeof window.tizen !== 'undefined',
        flutter: !!document.querySelector('flutter-view'),
        nativeBridge: !!window.MoonlightNative,
        wasm: typeof WebAssembly !== 'undefined',
        sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
        gamepads: !!navigator.getGamepads
      },
      input: window.MoonlightInput ? {
        mode: window.MoonlightInput.getMode(),
        devices: window.MoonlightInput.inputDevices()
      } : null,
      activeElement: document.activeElement ? {
        tagName: document.activeElement.tagName || '',
        id: document.activeElement.id || '',
        ariaLabel: document.activeElement.getAttribute &&
          document.activeElement.getAttribute('aria-label') || ''
      } : null
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
    var path = 'wgt-private/state/debug-bridge-client-id.txt';
    var handle = null;
    try {
      if (window.tizen && tizen.filesystem &&
          typeof tizen.filesystem.openFile === 'function') {
        try {
          handle = tizen.filesystem.openFile(path, 'r');
          if (typeof handle.readString === 'function') {
            var existing = String(handle.readString() || '');
            handle.close();
            handle = null;
            if (existing) {
              return existing;
            }
          }
        } catch (_) {
          if (handle && typeof handle.close === 'function') handle.close();
          handle = null;
        }
      }
      var created = 'flutter-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
      if (window.tizen && tizen.filesystem &&
          typeof tizen.filesystem.openFile === 'function') {
        handle = tizen.filesystem.openFile(path, 'w');
        if (typeof handle.writeString === 'function') handle.writeString(created);
      }
      return created;
    } catch (error) {
      return 'flutter-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
    } finally {
      if (handle && typeof handle.close === 'function') handle.close();
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
    if (type === 'nav') {
      var keys = {
        up: ['ArrowUp', 38],
        down: ['ArrowDown', 40],
        left: ['ArrowLeft', 37],
        right: ['ArrowRight', 39],
        accept: ['Enter', 13],
        back: ['XF86Back', 10009]
      };
      var key = keys[String(args.action || '')];
      if (!key) throw new Error('Unsupported nav action: ' + args.action);
      var event = new KeyboardEvent('keydown', {
        key: key[0],
        code: key[0],
        bubbles: true,
        cancelable: true
      });
      try { Object.defineProperty(event, 'keyCode', { value: key[1] }); } catch (_) {}
      document.dispatchEvent(event);
      document.dispatchEvent(new KeyboardEvent('keyup', {
        key: key[0],
        code: key[0],
        bubbles: true,
        cancelable: true
      }));
      return Promise.resolve({ action: args.action, dispatched: true });
    }
    if (type === 'click') {
      var target = document.querySelector(String(args.selector || ''));
      if (!target || typeof target.click !== 'function') {
        throw new Error('Clickable selector not found: ' + args.selector);
      }
      target.click();
      return Promise.resolve({ selector: args.selector, clicked: true });
    }
    if (type === 'setValue') {
      var input = document.querySelector(String(args.selector || ''));
      if (!input || !('value' in input)) {
        throw new Error('Input selector not found: ' + args.selector);
      }
      input.value = args.value == null ? '' : String(args.value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      return Promise.resolve({ selector: args.selector, changed: true });
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
