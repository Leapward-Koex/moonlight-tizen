(function() {
  'use strict';

  var LOG_LEVEL_KEY = 'moonlightLogLevel';
  var LOG_FILE_PATH = 'wgt-private/logs/moonlight-log.ndjson';
  var MAX_LOG_BYTES = 10 * 1024 * 1024;
  var MAX_MEMORY_ENTRIES = 200;
  var MAX_QUEUE_ENTRIES = 500;
  var FLUSH_DELAY_MS = 500;
  var LEVELS = {
    off: 0,
    error: 1,
    warn: 2,
    warning: 2,
    info: 3,
    log: 3,
    debug: 4
  };
  var LEVEL_LABELS = {
    off: 'Off',
    error: 'Error',
    warn: 'Warn',
    info: 'Info',
    debug: 'Debug'
  };
  var SENSITIVE_KEY_RE = /(password|passwd|passphrase|private|privatekey|certificate|cert|token|secret|rikey|rikeyid|sessionurl|rtsp|ppk|pin)/i;
  var PEM_RE = /-----BEGIN [^-]*(?:PRIVATE KEY|CERTIFICATE)[\s\S]*?-----END [^-]*(?:PRIVATE KEY|CERTIFICATE)-----/g;
  var URL_SECRET_RE = /([?&](?:rikey|rikeyid|token|secret|password|pin|key|privateKey|cert|sessionUrl)=)[^&\s]+/gi;
  var RTSP_RE = /rtsp:\/\/[^\s"'<>]+/gi;
  var REMOTE_INPUT_RE = /(Setting the Remote input key(?: ID)? to: )(.+)/gi;
  var RTSP_MESSAGE_RE = /(Setting the RTSP session URL to: )(.+)/gi;

  var originalConsole = {};
  var consoleWrapped = false;
  var inConsoleWrapper = false;
  var currentLevel = normalizeLevel(readStoredLevel());
  var fileQueue = [];
  var recentEntries = [];
  var sinks = [];
  var flushTimer = null;
  var flushing = false;
  var lastKnownSize = 0;
  var lastWriteFailed = false;

  function normalizeLevel(level) {
    var value = String(level || 'off').toLowerCase();
    if (value === 'warning') {
      value = 'warn';
    }
    return Object.prototype.hasOwnProperty.call(LEVELS, value) ? value : 'off';
  }

  function levelValue(level) {
    return LEVELS[normalizeLevel(level)];
  }

  function shouldPersist(level) {
    return currentLevel !== 'off' && levelValue(level) <= levelValue(currentLevel);
  }

  function readStoredLevel() {
    try {
      if (!window.localStorage) {
        return 'off';
      }
      return window.localStorage.getItem(LOG_LEVEL_KEY) || 'off';
    } catch (error) {
      return 'off';
    }
  }

  function writeStoredLevel(level) {
    try {
      if (window.localStorage) {
        window.localStorage.setItem(LOG_LEVEL_KEY, normalizeLevel(level));
      }
    } catch (error) {
      // Ignore storage failures. The IndexedDB mirror in index.js is best effort too.
    }
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function truncate(text, maxLength) {
    var value = String(text);
    return value.length > maxLength ? value.slice(0, maxLength) + '...[truncated]' : value;
  }

  function redactString(value) {
    return String(value)
      .replace(PEM_RE, '[redacted-pem]')
      .replace(RTSP_RE, '[redacted-rtsp-url]')
      .replace(URL_SECRET_RE, '$1[redacted]')
      .replace(REMOTE_INPUT_RE, '$1[redacted]')
      .replace(RTSP_MESSAGE_RE, '$1[redacted]');
  }

  function describeError(error) {
    return {
      name: redactString(error && error.name || 'Error'),
      message: redactString(error && error.message || String(error)),
      stack: error && error.stack ? truncate(redactString(error.stack), 8000) : ''
    };
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
      text: element.textContent ? truncate(redactString(element.textContent.trim()), 160) : ''
    };
  }

  function redactValue(value, key, seen) {
    if (SENSITIVE_KEY_RE.test(key || '')) {
      return '[redacted]';
    }
    if (value == null || typeof value === 'number' || typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'string') {
      return truncate(redactString(value), 8000);
    }
    if (value instanceof Error) {
      return describeError(value);
    }
    if (value && value.nodeType) {
      return describeElement(value);
    }
    if (typeof value === 'function') {
      return '[Function]';
    }
    if (typeof value !== 'object') {
      return truncate(redactString(String(value)), 8000);
    }
    if (seen.indexOf(value) !== -1) {
      return '[Circular]';
    }

    seen.push(value);
    if (Array.isArray(value)) {
      var arrayValue = [];
      for (var i = 0; i < value.length && i < 50; i += 1) {
        arrayValue.push(redactValue(value[i], '', seen));
      }
      if (value.length > 50) {
        arrayValue.push('...[truncated]');
      }
      seen.pop();
      return arrayValue;
    }

    var objectValue = {};
    var keys = Object.keys(value);
    for (var j = 0; j < keys.length && j < 50; j += 1) {
      objectValue[keys[j]] = redactValue(value[keys[j]], keys[j], seen);
    }
    if (keys.length > 50) {
      objectValue.truncated = true;
    }
    seen.pop();
    return objectValue;
  }

  function serializeArgs(argsLike) {
    var args = Array.prototype.slice.call(argsLike || []);
    var serialized = [];
    for (var i = 0; i < args.length && i < 20; i += 1) {
      serialized.push(redactValue(args[i], '', []));
    }
    if (args.length > 20) {
      serialized.push('...[truncated]');
    }
    return serialized;
  }

  function messageFromArgs(serializedArgs) {
    return truncate(serializedArgs.map(function(arg) {
      if (arg == null) {
        return String(arg);
      }
      if (typeof arg === 'string') {
        return arg;
      }
      if (typeof arg === 'number' || typeof arg === 'boolean') {
        return String(arg);
      }
      if (arg.name && arg.message) {
        return arg.name + ': ' + arg.message;
      }
      try {
        return JSON.stringify(arg);
      } catch (error) {
        return String(arg);
      }
    }).join(' '), 12000);
  }

  function textToBytes(text) {
    if (typeof TextEncoder !== 'undefined') {
      return new TextEncoder().encode(text);
    }
    var bytes = [];
    for (var i = 0; i < text.length; i += 1) {
      var code = text.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6));
        bytes.push(0x80 | (code & 0x3f));
      } else {
        bytes.push(0xe0 | (code >> 12));
        bytes.push(0x80 | ((code >> 6) & 0x3f));
        bytes.push(0x80 | (code & 0x3f));
      }
    }
    return bytes;
  }

  function byteLength(text) {
    return textToBytes(String(text)).length;
  }

  function filesystemAvailable() {
    return !!(window.tizen && tizen.filesystem && typeof tizen.filesystem.openFile === 'function');
  }

  function closeHandle(handle) {
    try {
      if (handle && typeof handle.close === 'function') {
        handle.close();
      }
    } catch (error) {
      // Closing failures are not actionable for users.
    }
  }

  function writeHandleText(handle, text) {
    if (typeof handle.writeString === 'function') {
      handle.writeString(text);
      return;
    }
    if (typeof handle.writeData === 'function') {
      handle.writeData(textToBytes(text));
    }
  }

  function openWriteHandle(path, mode) {
    return tizen.filesystem.openFile(path, mode);
  }

  function readLogText() {
    return new Promise(function(resolve) {
      if (!filesystemAvailable()) {
        resolve('');
        return;
      }

      var handle = null;
      try {
        handle = tizen.filesystem.openFile(LOG_FILE_PATH, 'r');
        if (typeof handle.readString === 'function') {
          var text = handle.readString();
          closeHandle(handle);
          resolve(text || '');
          return;
        }
        if (typeof handle.readBlob === 'function' && typeof FileReader !== 'undefined') {
          var blob = handle.readBlob();
          closeHandle(handle);
          var reader = new FileReader();
          reader.onload = function() {
            resolve(reader.result || '');
          };
          reader.onerror = function() {
            resolve('');
          };
          reader.readAsText(blob);
          return;
        }
        closeHandle(handle);
        resolve('');
      } catch (error) {
        closeHandle(handle);
        resolve('');
      }
    });
  }

  function replaceLogText(text) {
    if (!filesystemAvailable()) {
      return false;
    }
    var handle = null;
    try {
      handle = openWriteHandle(LOG_FILE_PATH, 'w');
      writeHandleText(handle, text);
      closeHandle(handle);
      lastKnownSize = byteLength(text);
      return true;
    } catch (error) {
      closeHandle(handle);
      return false;
    }
  }

  function trimTextToLimit(text) {
    var value = String(text || '');
    if (byteLength(value) <= MAX_LOG_BYTES) {
      return value;
    }

    var start = Math.max(0, value.length - MAX_LOG_BYTES);
    var trimmed = value.slice(start);
    var firstNewline = trimmed.indexOf('\n');
    if (firstNewline !== -1) {
      trimmed = trimmed.slice(firstNewline + 1);
    }
    return trimmed;
  }

  function rotateIfNeeded() {
    if (lastKnownSize <= MAX_LOG_BYTES) {
      return Promise.resolve();
    }

    return readLogText().then(function(text) {
      var trimmed = trimTextToLimit(text);
      if (trimmed !== text) {
        replaceLogText(trimmed);
      } else {
        lastKnownSize = byteLength(trimmed);
      }
    });
  }

  function appendLogText(text) {
    if (!filesystemAvailable()) {
      return false;
    }
    var handle = null;
    try {
      handle = openWriteHandle(LOG_FILE_PATH, 'a');
      writeHandleText(handle, text);
      closeHandle(handle);
      lastKnownSize += byteLength(text);
      return true;
    } catch (error) {
      closeHandle(handle);
      var readHandle = null;
      try {
        var existingText = '';
        try {
          readHandle = tizen.filesystem.openFile(LOG_FILE_PATH, 'r');
          if (typeof readHandle.readString === 'function') {
            existingText = readHandle.readString() || '';
          }
        } catch (readError) {
          existingText = '';
        } finally {
          closeHandle(readHandle);
        }

        var combinedText = trimTextToLimit(existingText + text);
        return replaceLogText(combinedText);
      } catch (fallbackError) {
        return false;
      }
    }
  }

  function scheduleFlush() {
    if (flushTimer) {
      return;
    }
    flushTimer = window.setTimeout(function() {
      flushTimer = null;
      flush();
    }, FLUSH_DELAY_MS);
  }

  function flush() {
    if (flushing || fileQueue.length === 0) {
      return Promise.resolve();
    }
    if (!filesystemAvailable()) {
      scheduleFlush();
      return Promise.resolve();
    }

    flushing = true;
    var entries = fileQueue.splice(0, 100);
    var text = entries.map(function(entry) {
      return JSON.stringify(entry);
    }).join('\n') + '\n';

    var wrote = appendLogText(text);
    if (!wrote) {
      fileQueue = entries.concat(fileQueue).slice(-MAX_QUEUE_ENTRIES);
      lastWriteFailed = true;
      flushing = false;
      scheduleFlush();
      return Promise.resolve();
    }

    lastWriteFailed = false;
    return rotateIfNeeded().then(function() {
      flushing = false;
      if (fileQueue.length > 0) {
        scheduleFlush();
      }
    });
  }

  function addRecentEntry(entry) {
    recentEntries.push(entry);
    if (recentEntries.length > MAX_MEMORY_ENTRIES) {
      recentEntries.splice(0, recentEntries.length - MAX_MEMORY_ENTRIES);
    }
  }

  function notifySinks(entry) {
    sinks.slice().forEach(function(sink) {
      try {
        sink(entry);
      } catch (error) {
        // Sink failures must not affect app logging.
      }
    });
  }

  function createEntry(level, argsLike, meta) {
    var normalizedLevel = normalizeLevel(level === 'log' ? 'info' : level);
    var serializedArgs = serializeArgs(argsLike);
    return {
      time: nowIso(),
      level: normalizedLevel,
      message: messageFromArgs(serializedArgs),
      args: serializedArgs,
      meta: redactValue(meta || {}, '', [])
    };
  }

  function capture(level, argsLike, meta) {
    var persist = shouldPersist(level);
    if (!persist && sinks.length === 0 && recentEntries.length >= MAX_MEMORY_ENTRIES) {
      return null;
    }

    var entry = createEntry(level, argsLike, meta);
    addRecentEntry(entry);
    notifySinks(entry);

    if (persist) {
      fileQueue.push(entry);
      if (fileQueue.length > MAX_QUEUE_ENTRIES) {
        fileQueue.splice(0, fileQueue.length - MAX_QUEUE_ENTRIES);
      }
      scheduleFlush();
    }
    return entry;
  }

  function wrapConsole() {
    if (consoleWrapped) {
      return;
    }
    var consoleObject = window.console = window.console || {};
    ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
      var original = typeof consoleObject[level] === 'function' ? consoleObject[level] : function() {};
      originalConsole[level] = original.bind ? original.bind(consoleObject) : original;
      consoleObject[level] = function() {
        originalConsole[level].apply(consoleObject, arguments);
        if (!inConsoleWrapper) {
          inConsoleWrapper = true;
          try {
            capture(level, arguments, { source: 'console' });
          } finally {
            inConsoleWrapper = false;
          }
        }
      };
    });
    consoleWrapped = true;
  }

  function installErrorHandlers() {
    window.addEventListener('error', function(event) {
      capture('error', [event.message || 'window error'], {
        source: 'window.onerror',
        filename: event.filename || '',
        lineno: event.lineno || 0,
        colno: event.colno || 0,
        error: event.error ? describeError(event.error) : null
      });
    });

    window.addEventListener('unhandledrejection', function(event) {
      capture('error', ['unhandledrejection', event.reason], {
        source: 'unhandledrejection'
      });
    });
  }

  function installGlobalHelper() {
    window.moonlightDebugLog = function(level) {
      capture(level || 'info', Array.prototype.slice.call(arguments, 1), { source: 'manual' });
    };
  }

  function getStatus() {
    return readLogText().then(function(text) {
      lastKnownSize = byteLength(text);
      return {
        level: currentLevel,
        levelLabel: LEVEL_LABELS[currentLevel],
        path: LOG_FILE_PATH,
        maxBytes: MAX_LOG_BYTES,
        sizeBytes: lastKnownSize,
        available: filesystemAvailable(),
        pendingEntries: fileQueue.length,
        lastWriteFailed: lastWriteFailed
      };
    });
  }

  function clearLogs() {
    fileQueue = [];
    lastKnownSize = 0;
    if (!filesystemAvailable()) {
      return Promise.resolve(false);
    }

    return new Promise(function(resolve) {
      try {
        if (tizen.filesystem.deleteFile) {
          tizen.filesystem.deleteFile(LOG_FILE_PATH);
          resolve(true);
          return;
        }
      } catch (error) {
        // Fall back to truncation below.
      }
      resolve(replaceLogText(''));
    });
  }

  function getExportText() {
    return flush().then(readLogText).then(function(text) {
      var trimmed = trimTextToLimit(redactString(text || ''));
      return trimmed;
    });
  }

  function setLevel(level) {
    currentLevel = normalizeLevel(level);
    writeStoredLevel(currentLevel);
    if (currentLevel !== 'off') {
      capture('info', ['Moonlight file logging enabled', currentLevel], { source: 'logger' });
    }
    return currentLevel;
  }

  function addSink(sink, options) {
    if (typeof sink !== 'function') {
      return function() {};
    }
    sinks.push(sink);
    if (!options || options.replay !== false) {
      recentEntries.forEach(function(entry) {
        try {
          sink(entry);
        } catch (error) {
          // Ignore replay sink failures.
        }
      });
    }
    return function() {
      var index = sinks.indexOf(sink);
      if (index !== -1) {
        sinks.splice(index, 1);
      }
    };
  }

  function getLevels() {
    return [
      { value: 'off', label: 'Off' },
      { value: 'error', label: 'Error' },
      { value: 'warn', label: 'Warn' },
      { value: 'info', label: 'Info' },
      { value: 'debug', label: 'Debug' }
    ];
  }

  function escapeXml(text) {
    return String(text).replace(/[&<>"']/g, function(ch) {
      return {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[ch];
    });
  }

  function gfMul(x, y) {
    var result = 0;
    while (y !== 0) {
      if (y & 1) {
        result ^= x;
      }
      x <<= 1;
      if (x & 0x100) {
        x ^= 0x11d;
      }
      y >>= 1;
    }
    return result;
  }

  function reedSolomonGenerator(degree) {
    var result = new Array(degree).fill(0);
    result[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i += 1) {
      for (var j = 0; j < degree; j += 1) {
        result[j] = gfMul(result[j], root);
        if (j + 1 < degree) {
          result[j] ^= result[j + 1];
        }
      }
      root = gfMul(root, 2);
    }
    return result;
  }

  function reedSolomonRemainder(data, degree) {
    var generator = reedSolomonGenerator(degree);
    var result = new Array(degree).fill(0);
    data.forEach(function(value) {
      var factor = value ^ result.shift();
      result.push(0);
      for (var i = 0; i < degree; i += 1) {
        result[i] ^= gfMul(generator[i], factor);
      }
    });
    return result;
  }

  function appendBits(bits, value, length) {
    for (var i = length - 1; i >= 0; i -= 1) {
      bits.push((value >>> i) & 1);
    }
  }

  function makeQrCodewords(text) {
    var bytes = textToBytes(text);
    var dataCodewords = 108;
    var ecCodewords = 26;
    var bits = [];
    appendBits(bits, 0x4, 4);
    appendBits(bits, bytes.length, 8);
    for (var i = 0; i < bytes.length; i += 1) {
      appendBits(bits, bytes[i], 8);
    }

    var maxBits = dataCodewords * 8;
    appendBits(bits, 0, Math.min(4, maxBits - bits.length));
    while (bits.length % 8 !== 0) {
      bits.push(0);
    }

    var data = [];
    for (var j = 0; j < bits.length; j += 8) {
      var codeword = 0;
      for (var k = 0; k < 8; k += 1) {
        codeword = (codeword << 1) | bits[j + k];
      }
      data.push(codeword);
    }
    var pad = 0xec;
    while (data.length < dataCodewords) {
      data.push(pad);
      pad = pad === 0xec ? 0x11 : 0xec;
    }
    return data.concat(reedSolomonRemainder(data, ecCodewords));
  }

  function makeMatrix(size) {
    var modules = [];
    var reserved = [];
    for (var y = 0; y < size; y += 1) {
      modules.push(new Array(size).fill(false));
      reserved.push(new Array(size).fill(false));
    }
    return { modules: modules, reserved: reserved };
  }

  function setModule(matrix, x, y, value, reserve) {
    if (x < 0 || y < 0 || y >= matrix.modules.length || x >= matrix.modules.length) {
      return;
    }
    matrix.modules[y][x] = !!value;
    if (reserve) {
      matrix.reserved[y][x] = true;
    }
  }

  function drawFinder(matrix, x, y) {
    for (var dy = -1; dy <= 7; dy += 1) {
      for (var dx = -1; dx <= 7; dx += 1) {
        var xx = x + dx;
        var yy = y + dy;
        var black = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6 &&
          (dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
        setModule(matrix, xx, yy, black, true);
      }
    }
  }

  function drawAlignment(matrix, x, y) {
    for (var dy = -2; dy <= 2; dy += 1) {
      for (var dx = -2; dx <= 2; dx += 1) {
        var distance = Math.max(Math.abs(dx), Math.abs(dy));
        setModule(matrix, x + dx, y + dy, distance !== 1, true);
      }
    }
  }

  function drawFunctionPatterns(matrix) {
    var size = matrix.modules.length;
    drawFinder(matrix, 0, 0);
    drawFinder(matrix, size - 7, 0);
    drawFinder(matrix, 0, size - 7);
    drawAlignment(matrix, 30, 30);

    for (var i = 0; i < size; i += 1) {
      if (!matrix.reserved[6][i]) {
        setModule(matrix, i, 6, i % 2 === 0, true);
      }
      if (!matrix.reserved[i][6]) {
        setModule(matrix, 6, i, i % 2 === 0, true);
      }
    }

    for (var j = 0; j < 8; j += 1) {
      setModule(matrix, 8, j, false, true);
      setModule(matrix, j, 8, false, true);
      setModule(matrix, size - 1 - j, 8, false, true);
      setModule(matrix, 8, size - 1 - j, false, true);
    }
    setModule(matrix, 8, 8, false, true);
    setModule(matrix, 8, 29, true, true);
  }

  function maskBit(mask, x, y) {
    switch (mask) {
      case 0: return (x + y) % 2 === 0;
      case 1: return y % 2 === 0;
      case 2: return x % 3 === 0;
      default: return (x + y) % 2 === 0;
    }
  }

  function placeData(matrix, codewords, mask) {
    var size = matrix.modules.length;
    var bits = [];
    codewords.forEach(function(codeword) {
      appendBits(bits, codeword, 8);
    });
    var index = 0;
    var upward = true;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right === 6) {
        right -= 1;
      }
      for (var vert = 0; vert < size; vert += 1) {
        var y = upward ? size - 1 - vert : vert;
        for (var j = 0; j < 2; j += 1) {
          var x = right - j;
          if (matrix.reserved[y][x]) {
            continue;
          }
          var bit = index < bits.length ? bits[index] === 1 : false;
          if (maskBit(mask, x, y)) {
            bit = !bit;
          }
          setModule(matrix, x, y, bit, false);
          index += 1;
        }
      }
      upward = !upward;
    }
  }

  function bchFormatBits(eccLevel, mask) {
    var data = (eccLevel << 3) | mask;
    var value = data << 10;
    var generator = 0x537;
    for (var i = 14; i >= 10; i -= 1) {
      if ((value >>> i) & 1) {
        value ^= generator << (i - 10);
      }
    }
    return ((data << 10) | value) ^ 0x5412;
  }

  function drawFormatBits(matrix, mask) {
    var size = matrix.modules.length;
    var bits = bchFormatBits(1, mask);
    for (var i = 0; i <= 5; i += 1) {
      setModule(matrix, 8, i, ((bits >>> i) & 1) !== 0, true);
    }
    setModule(matrix, 8, 7, ((bits >>> 6) & 1) !== 0, true);
    setModule(matrix, 8, 8, ((bits >>> 7) & 1) !== 0, true);
    setModule(matrix, 7, 8, ((bits >>> 8) & 1) !== 0, true);
    for (var j = 9; j < 15; j += 1) {
      setModule(matrix, 14 - j, 8, ((bits >>> j) & 1) !== 0, true);
    }
    for (var k = 0; k < 8; k += 1) {
      setModule(matrix, size - 1 - k, 8, ((bits >>> k) & 1) !== 0, true);
    }
    for (var m = 8; m < 15; m += 1) {
      setModule(matrix, 8, size - 15 + m, ((bits >>> m) & 1) !== 0, true);
    }
  }

  function makeQrSvg(text) {
    if (textToBytes(text).length > 104) {
      return '';
    }

    var size = 37;
    var border = 4;
    var mask = 0;
    var matrix = makeMatrix(size);
    drawFunctionPatterns(matrix);
    placeData(matrix, makeQrCodewords(text), mask);
    drawFormatBits(matrix, mask);

    var rects = [];
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        if (matrix.modules[y][x]) {
          rects.push('<rect x="' + (x + border) + '" y="' + (y + border) + '" width="1" height="1"/>');
        }
      }
    }
    var viewBox = '0 0 ' + (size + border * 2) + ' ' + (size + border * 2);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + viewBox + '" role="img" aria-label="Log export QR code">' +
      '<rect width="100%" height="100%" fill="#fff"/><g fill="#000">' + rects.join('') + '</g></svg>';
  }

  function renderQrCode(text, element) {
    if (!element) {
      return false;
    }
    var svg = makeQrSvg(String(text || ''));
    if (!svg) {
      element.textContent = 'URL is too long for QR display.';
      return false;
    }
    element.innerHTML = svg;
    return true;
  }

  wrapConsole();
  installErrorHandlers();
  installGlobalHelper();

  window.MoonlightLogger = {
    levels: getLevels,
    getLevel: function() {
      return currentLevel;
    },
    getLevelLabel: function(level) {
      return LEVEL_LABELS[normalizeLevel(level)];
    },
    setLevel: setLevel,
    log: capture,
    flush: flush,
    getStatus: getStatus,
    clear: clearLogs,
    getExportText: getExportText,
    addSink: addSink,
    installGlobalHelper: installGlobalHelper,
    renderQrCode: renderQrCode,
    redactString: redactString,
    logPath: LOG_FILE_PATH,
    maxBytes: MAX_LOG_BYTES,
    storageKey: LOG_LEVEL_KEY
  };
})();
