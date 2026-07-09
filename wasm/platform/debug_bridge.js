(function() {
  'use strict';

  var config = window.MOONLIGHT_DEBUG_BRIDGE || {};
  var disabledApi = {
    enabled: false,
    log: function() {},
    flush: function() {},
    executeCommand: function() {
      throw new Error('Moonlight debug bridge is disabled');
    }
  };

  function installDebugLogHelper() {
    if (window.MoonlightLogger && typeof window.MoonlightLogger.installGlobalHelper === 'function') {
      window.MoonlightLogger.installGlobalHelper();
      return;
    }

    window.moonlightDebugLog = function(level) {
      var bridge = window.MoonlightDebugBridge;
      if (!bridge || typeof bridge.log !== 'function') {
        return;
      }
      bridge.log.apply(bridge, arguments);
    };
  }

  if (!config.enabled || !config.serverUrl || !config.token) {
    window.MoonlightDebugBridge = disabledApi;
    installDebugLogHelper();
    return;
  }

  var serverUrl = String(config.serverUrl).replace(/\/+$/, '');
  var token = String(config.token);
  var clientName = String(config.clientName || 'tizen-emulator');
  var basePollMs = positiveNumber(config.pollMs, 1000);
  var maxPollMs = positiveNumber(config.maxPollMs, 8000);
  var flushDelayMs = positiveNumber(config.flushMs, 500);
  var maxQueueSize = positiveNumber(config.maxQueueSize, 500);
  var clientId = getClientId();
  var originalConsole = {};
  var queue = [];
  var flushTimer = null;
  var flushing = false;
  var pollTimer = null;
  var currentPollMs = basePollMs;

  function positiveNumber(value, fallback) {
    var number = Number(value);
    return isFinite(number) && number > 0 ? number : fallback;
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function makeId(prefix) {
    var randomPart = Math.random().toString(36).slice(2);
    var timePart = Date.now().toString(36);
    return prefix + '-' + timePart + '-' + randomPart;
  }

  function getClientId() {
    var key = 'moonlightDebugBridgeClientId';
    try {
      var existing = window.localStorage && window.localStorage.getItem(key);
      if (existing) {
        return existing;
      }

      var created = makeId('tizen');
      window.localStorage.setItem(key, created);
      return created;
    } catch (error) {
      return makeId('tizen');
    }
  }

  function truncate(text, maxLength) {
    var value = String(text);
    if (value.length <= maxLength) {
      return value;
    }
    return value.slice(0, maxLength) + '...[truncated]';
  }

  function describeElement(element) {
    if (!element) {
      return null;
    }

    return {
      tagName: element.tagName || '',
      id: element.id || '',
      className: typeof element.className === 'string' ? element.className : '',
      name: element.getAttribute ? element.getAttribute('name') || '' : '',
      text: element.textContent ? truncate(element.textContent.trim(), 160) : ''
    };
  }

  function serializeError(error) {
    if (!error) {
      return { message: '' };
    }

    return {
      name: error.name || 'Error',
      message: error.message || String(error),
      stack: error.stack ? truncate(error.stack, 8000) : ''
    };
  }

  function serializeArg(value) {
    if (value == null || typeof value === 'number' || typeof value === 'boolean') {
      return value;
    }

    if (typeof value === 'string') {
      return truncate(value, 8000);
    }

    if (value instanceof Error) {
      return serializeError(value);
    }

    if (value && value.nodeType) {
      return describeElement(value);
    }

    if (typeof value === 'function') {
      return '[Function]';
    }

    try {
      var seen = [];
      var json = JSON.stringify(value, function(key, item) {
        if (item && item.nodeType) {
          return describeElement(item);
        }
        if (item instanceof Error) {
          return serializeError(item);
        }
        if (typeof item === 'function') {
          return '[Function]';
        }
        if (typeof item === 'string') {
          return truncate(item, 8000);
        }
        if (item && typeof item === 'object') {
          if (seen.indexOf(item) !== -1) {
            return '[Circular]';
          }
          seen.push(item);
        }
        return item;
      });
      return JSON.parse(truncate(json, 12000));
    } catch (error) {
      return truncate(String(value), 8000);
    }
  }

  function serializeArgs(argsLike) {
    var args = Array.prototype.slice.call(argsLike || []);
    return args.slice(0, 20).map(serializeArg);
  }

  function messageFromArgs(serializedArgs) {
    return serializedArgs.map(function(arg) {
      if (arg == null) {
        return String(arg);
      }
      if (typeof arg === 'string') {
        return arg;
      }
      if (typeof arg === 'number' || typeof arg === 'boolean') {
        return String(arg);
      }
      if (arg.message && arg.name) {
        return arg.name + ': ' + arg.message;
      }
      try {
        return JSON.stringify(arg);
      } catch (error) {
        return String(arg);
      }
    }).join(' ');
  }

  function enqueue(level, argsLike, meta) {
    var serializedArgs = serializeArgs(argsLike);
    queue.push({
      time: nowIso(),
      level: level,
      message: truncate(messageFromArgs(serializedArgs), 12000),
      args: serializedArgs,
      meta: meta || {}
    });

    if (queue.length > maxQueueSize) {
      queue.splice(0, queue.length - maxQueueSize);
    }

    scheduleFlush(flushDelayMs);
  }

  function scheduleFlush(delayMs) {
    if (flushTimer) {
      return;
    }

    flushTimer = window.setTimeout(function() {
      flushTimer = null;
      flush();
    }, delayMs);
  }

  function parseJson(text) {
    if (!text) {
      return {};
    }
    return JSON.parse(text);
  }

  function requestJson(method, path, body) {
    var url = serverUrl + path;
    var payload = body == null ? null : JSON.stringify(body);

    if (window.fetch) {
      return window.fetch(url, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-Debug-Token': token
        },
        body: payload
      }).then(function(response) {
        return response.text().then(function(text) {
          var parsed = parseJson(text);
          if (!response.ok) {
            throw new Error(parsed.error || ('HTTP ' + response.status));
          }
          return parsed;
        });
      });
    }

    return new Promise(function(resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open(method, url, true);
      xhr.setRequestHeader('Content-Type', 'application/json');
      xhr.setRequestHeader('X-Debug-Token', token);
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) {
          return;
        }

        var parsed;
        try {
          parsed = parseJson(xhr.responseText);
        } catch (error) {
          reject(error);
          return;
        }

        if (xhr.status < 200 || xhr.status >= 300) {
          reject(new Error(parsed.error || ('HTTP ' + xhr.status)));
          return;
        }
        resolve(parsed);
      };
      xhr.onerror = function() {
        reject(new Error('XHR network error'));
      };
      xhr.send(payload);
    });
  }

  function subscribeToMoonlightLogger() {
    if (!window.MoonlightLogger || typeof window.MoonlightLogger.addSink !== 'function') {
      return false;
    }

    window.MoonlightLogger.addSink(function(entry) {
      if (!entry) {
        return;
      }
      enqueue(entry.level || 'info', entry.args || [entry.message || ''], Object.assign({
        source: 'moonlight-logger'
      }, entry.meta || {}));
    });
    return true;
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

  function wrapConsole() {
    var consoleObject = window.console = window.console || {};
    ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
      var original = typeof consoleObject[level] === 'function' ? consoleObject[level] : function() {};
      originalConsole[level] = original.bind ? original.bind(consoleObject) : original;
      consoleObject[level] = function() {
        originalConsole[level].apply(consoleObject, arguments);
        enqueue(level, arguments, { source: 'console' });
      };
    });
  }

  function dispatchBubblingEvent(element, name) {
    var event;
    if (typeof Event === 'function') {
      event = new Event(name, { bubbles: true, cancelable: true });
    } else {
      event = document.createEvent('Event');
      event.initEvent(name, true, true);
    }
    element.dispatchEvent(event);
  }

  function setElementValue(element, value) {
    element.focus();
    element.value = value == null ? '' : String(value);
    dispatchBubblingEvent(element, 'input');
    dispatchBubblingEvent(element, 'change');
  }

  function getRequiredSelector(args) {
    var selector = args && args.selector;
    if (!selector || typeof selector !== 'string') {
      throw new Error('selector is required');
    }
    return selector;
  }

  function getElementBySelector(selector) {
    var element = document.querySelector(selector);
    if (!element) {
      throw new Error('No element matched selector: ' + selector);
    }
    return element;
  }

  function executeNav(args) {
    var action = String(args && (args.action || args.direction || args.key) || '').toLowerCase();
    var allowed = {
      up: true,
      down: true,
      left: true,
      right: true,
      accept: true,
      back: true,
      switch: true,
      press: true
    };

    if (!allowed[action]) {
      throw new Error('Unsupported nav action: ' + action);
    }
    if (typeof Navigation === 'undefined' || typeof Navigation[action] !== 'function') {
      throw new Error('Navigation is not ready');
    }

    Navigation[action]();
    return { action: action };
  }

  function executeClick(args) {
    var selector = getRequiredSelector(args);
    var element = getElementBySelector(selector);
    element.click();
    return { clicked: describeElement(element) };
  }

  function executeSetValue(args) {
    var selector = getRequiredSelector(args);
    var element = getElementBySelector(selector);
    setElementValue(element, args ? args.value : '');
    return { element: describeElement(element), value: element.value };
  }

  function delay(ms) {
    return new Promise(function(resolve) {
      window.setTimeout(resolve, ms);
    });
  }

  function addHostDialogIsOpen() {
    var dialog = document.getElementById('addHostDialog');
    return !!(dialog && dialog.open);
  }

  function openAddHostDialog() {
    if (addHostDialogIsOpen()) {
      return Promise.resolve({ alreadyOpen: true });
    }

    if (typeof addHostDialog === 'function') {
      addHostDialog();
      return delay(150).then(function() {
        return { openedVia: 'addHostDialog' };
      });
    }

    var addHostButton = document.getElementById('addHostContainer');
    if (addHostButton) {
      addHostButton.click();
      return delay(150).then(function() {
        return { openedVia: '#addHostContainer' };
      });
    }

    throw new Error('Add Host UI is not available');
  }

  function useAddHostTextMode() {
    var modeSwitch = document.getElementById('ipAddressFieldModeSwitch');
    if (modeSwitch && modeSwitch.checked) {
      modeSwitch.checked = false;
      var materialSwitch = document.getElementById('ipAddressFieldModeBtn');
      if (materialSwitch && materialSwitch.MaterialSwitch && typeof materialSwitch.MaterialSwitch.off === 'function') {
        materialSwitch.MaterialSwitch.off();
      }
      if (typeof handleIpAddressFieldMode === 'function') {
        handleIpAddressFieldMode();
      }
    }
  }

  function executeAddHost(args) {
    var address = args && (args.address || args.host || args.value);
    if (!address || typeof address !== 'string') {
      throw new Error('address is required');
    }

    return openAddHostDialog().then(function(openResult) {
      useAddHostTextMode();

      var input = document.getElementById('ipAddressTextInput');
      if (!input) {
        throw new Error('#ipAddressTextInput was not found');
      }

      input.readOnly = false;
      setElementValue(input, address);

      if (typeof updateIpAddressInputValidationState === 'function') {
        updateIpAddressInputValidationState();
      }

      var continueButton = document.getElementById('continueAddHost');
      if (!continueButton) {
        throw new Error('#continueAddHost was not found');
      }

      if (continueButton.disabled) {
        continueButton.disabled = false;
        if (continueButton.classList) {
          continueButton.classList.remove('mdl-button--disabled');
        }
      }

      continueButton.click();
      return {
        address: address,
        openResult: openResult,
        clicked: describeElement(continueButton)
      };
    });
  }

  function isVisible(element) {
    if (!element) {
      return false;
    }
    var style = window.getComputedStyle ? window.getComputedStyle(element) : null;
    if (style && (style.display === 'none' || style.visibility === 'hidden')) {
      return false;
    }
    return !!(element.open || element.offsetWidth || element.offsetHeight || element.getClientRects().length);
  }

  function collectVisibleDialogs() {
    var nodes = document.querySelectorAll('dialog, .dialog-overlay, .mdl-dialog');
    var dialogs = [];
    for (var i = 0; i < nodes.length; i += 1) {
      if (isVisible(nodes[i])) {
        dialogs.push(describeElement(nodes[i]));
      }
    }
    return dialogs;
  }

  function collectSelectedElements() {
    var nodes = document.querySelectorAll(':focus, .is-focused, .selected, [aria-selected="true"]');
    var selected = [];
    for (var i = 0; i < nodes.length && selected.length < 30; i += 1) {
      selected.push(describeElement(nodes[i]));
    }
    return selected;
  }

  function safeGlobalValue(name) {
    try {
      if (name === 'isDialogOpen' && typeof isDialogOpen !== 'undefined') {
        return isDialogOpen;
      }
      if (name === 'isInGame' && typeof isInGame !== 'undefined') {
        return isInGame;
      }
      if (name === 'isPairingInProgress' && typeof isPairingInProgress !== 'undefined') {
        return isPairingInProgress;
      }
    } catch (error) {
      return null;
    }
    return null;
  }

  function executeGetState() {
    var hostCount = null;
    var hostIds = [];
    try {
      if (typeof hosts !== 'undefined' && hosts) {
        hostIds = Object.keys(hosts);
        hostCount = hostIds.length;
      }
    } catch (error) {
      hostCount = null;
    }

    return {
      href: window.location.href,
      readyState: document.readyState,
      title: document.title,
      activeElement: describeElement(document.activeElement),
      visibleDialogs: collectVisibleDialogs(),
      selectedElements: collectSelectedElements(),
      hostCount: hostCount,
      hostIds: hostIds.slice(0, 50),
      globals: {
        isDialogOpen: safeGlobalValue('isDialogOpen'),
        isInGame: safeGlobalValue('isInGame'),
        isPairingInProgress: safeGlobalValue('isPairingInProgress'),
        hasNavigation: typeof Navigation !== 'undefined',
        hasAddHostDialog: typeof addHostDialog === 'function',
        hasTizenTvWasm: typeof window.tizentvwasm !== 'undefined',
        hasTizenSocketHostBindings: !!(window.tizentvwasm && window.tizentvwasm.SocketsHostBindings),
        hasTizenSocketManager: !!(window.tizentvwasm && window.tizentvwasm.SocketsManager),
        hasSharedArrayBuffer: typeof window.SharedArrayBuffer !== 'undefined'
      }
    };
  }

  function executeLocalStorage(args) {
    var action = String(args && (args.action || args.op) || 'get').toLowerCase();
    var key = args && args.key;
    if (!key || typeof key !== 'string') {
      throw new Error('key is required');
    }

    if (action === 'get') {
      return { key: key, value: window.localStorage.getItem(key) };
    }
    if (action === 'set') {
      window.localStorage.setItem(key, args.value == null ? '' : String(args.value));
      return { key: key, value: window.localStorage.getItem(key) };
    }
    if (action === 'remove') {
      window.localStorage.removeItem(key);
      return { key: key, removed: true };
    }

    throw new Error('Unsupported localStorage action: ' + action);
  }

  function executeReload(args) {
    var delayMs = args && args.delayMs ? Number(args.delayMs) : 0;
    window.setTimeout(function() {
      window.location.reload();
    }, isFinite(delayMs) && delayMs >= 0 ? delayMs : 0);
    return { scheduled: true };
  }

  function executeCommand(command) {
    var args = command && command.args || {};
    if (!command || !command.type) {
      throw new Error('command.type is required');
    }

    if (command.type === 'nav') {
      return executeNav(args);
    }
    if (command.type === 'click') {
      return executeClick(args);
    }
    if (command.type === 'setValue') {
      return executeSetValue(args);
    }
    if (command.type === 'addHost') {
      return executeAddHost(args);
    }
    if (command.type === 'getState') {
      return executeGetState(args);
    }
    if (command.type === 'localStorage') {
      return executeLocalStorage(args);
    }
    if (command.type === 'reload') {
      return executeReload(args);
    }

    throw new Error('Unsupported command type: ' + command.type);
  }

  function sendCommandResult(command, ok, result, error) {
    return requestJson('POST', '/api/commands/' + encodeURIComponent(command.id) + '/result', {
      clientId: clientId,
      commandId: command.id,
      ok: ok,
      result: result || {},
      error: error ? serializeError(error) : null
    });
  }

  function runCommand(command) {
    return Promise.resolve().then(function() {
      return executeCommand(command);
    }).then(function(result) {
      enqueue('info', ['debug command completed', command.type, command.id], { source: 'debug-bridge-command' });
      return sendCommandResult(command, true, result, null);
    }, function(error) {
      enqueue('error', ['debug command failed', command.type, command.id, error], { source: 'debug-bridge-command' });
      return sendCommandResult(command, false, {}, error);
    }).then(null, function(error) {
      enqueue('warn', ['debug command result post failed', command.type, command.id, error], { source: 'debug-bridge-command' });
    });
  }

  function pollCommands() {
    requestJson('GET', '/api/commands?clientId=' + encodeURIComponent(clientId)).then(function(response) {
      currentPollMs = basePollMs;
      var commands = response && response.commands || [];
      var chain = Promise.resolve();
      commands.forEach(function(command) {
        chain = chain.then(function() {
          return runCommand(command);
        });
      });
      return chain;
    }, function() {
      currentPollMs = Math.min(maxPollMs, Math.max(basePollMs, Math.round(currentPollMs * 1.5)));
    }).then(function() {
      pollTimer = window.setTimeout(pollCommands, currentPollMs);
    });
  }

  function markLifecycle(name, meta) {
    enqueue('info', ['lifecycle', name], Object.assign({
      source: 'lifecycle',
      readyState: document.readyState
    }, meta || {}));
  }

  if (!subscribeToMoonlightLogger()) {
    wrapConsole();

    window.addEventListener('error', function(event) {
      enqueue('error', [event.message || 'window error'], {
        source: 'window.onerror',
        filename: event.filename || '',
        lineno: event.lineno || 0,
        colno: event.colno || 0,
        error: event.error ? serializeError(event.error) : null
      });
    });

    window.addEventListener('unhandledrejection', function(event) {
      enqueue('error', ['unhandledrejection', event.reason], {
        source: 'unhandledrejection'
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      markLifecycle('DOMContentLoaded');
    });
  } else {
    markLifecycle('DOMContentLoaded-already-fired');
  }

  window.addEventListener('load', function() {
    markLifecycle('load');
  });

  window.MoonlightDebugBridge = {
    enabled: true,
    clientId: clientId,
    clientName: clientName,
    log: function(level) {
      enqueue(level || 'log', Array.prototype.slice.call(arguments, 1), { source: 'manual' });
    },
    flush: flush,
    getState: executeGetState,
    executeCommand: executeCommand
  };
  installDebugLogHelper();

  enqueue('info', ['debug bridge enabled', clientId], {
    source: 'debug-bridge',
    serverUrl: serverUrl,
    clientName: clientName,
    readyState: document.readyState
  });

  pollTimer = window.setTimeout(pollCommands, basePollMs);
})();
