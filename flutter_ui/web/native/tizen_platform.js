(function installMoonlightTizenPlatform(root) {
  'use strict';

  if (root.MoonlightTizenPlatform) {
    return;
  }

  var DEFAULT_KEYS = [
    'ColorF0Red',
    'ColorF1Green',
    'ColorF2Yellow',
    'ColorF3Blue',
    'Source',
    'ChannelList',
    'ChannelDown',
    'ChannelUp'
  ];

  function safeRead(reader, fallback) {
    try {
      var value = reader();
      return value == null ? fallback : value;
    } catch (_) {
      return fallback;
    }
  }

  function getTizen() {
    return root.tizen || null;
  }

  function getWebApis() {
    return root.webapis || null;
  }

  function getAppInfo() {
    var tizen = getTizen();
    var info = safeRead(function() {
      return tizen && tizen.application && tizen.application.getAppInfo();
    }, null);
    return {
      id: info && info.id ? String(info.id) : '',
      packageId: info && info.packageId ? String(info.packageId) : '',
      name: info && info.name ? String(info.name) : 'Moonlight Flutter',
      version: info && info.version ? String(info.version) : '0.0.0'
    };
  }

  function productInfoValue(method, fallback) {
    return safeRead(function() {
      var webapis = getWebApis();
      var productInfo = webapis && webapis.productinfo;
      return productInfo && typeof productInfo[method] === 'function'
        ? productInfo[method]()
        : fallback;
    }, fallback);
  }

  function getPlatformInfo() {
    var tizen = getTizen();
    var platformVersion = safeRead(function() {
      return tizen && tizen.systeminfo && tizen.systeminfo.getCapability(
        'http://tizen.org/feature/platform.version'
      );
    }, '');
    var is4k = !!productInfoValue('isUdPanelSupported', false);
    var is8k = !!productInfoValue('is8KPanelSupported', false);
    var screenWidth = safeRead(function() { return root.screen.width; }, 1920);
    var screenHeight = safeRead(function() { return root.screen.height; }, 1080);
    var maximumWidth = is8k ? 7680 : (is4k ? 3840 : (screenWidth >= 2560 ? 2560 : 1920));
    var maximumHeight = is8k ? 4320 : (is4k ? 2160 : (screenHeight >= 1440 ? 1440 : 1080));
    var webapis = getWebApis();
    var hdr = !!safeRead(function() {
      return webapis && webapis.avinfo && webapis.avinfo.isHdrTvSupport();
    }, false);

    return {
      isTizen: !!tizen,
      hasSamsungWebApis: !!webapis,
      app: getAppInfo(),
      platformVersion: String(platformVersion || ''),
      modelSeries: String(productInfoValue('getModel', '') || ''),
      modelName: String(productInfoValue('getRealModel', '') || ''),
      modelGroup: String(productInfoValue('getModelCode', '') || ''),
      is4kPanel: is4k,
      is8kPanel: is8k,
      isHdrCapable: hdr,
      maximumWidth: maximumWidth,
      maximumHeight: maximumHeight,
      screenWidth: Number(screenWidth) || 0,
      screenHeight: Number(screenHeight) || 0,
      supportsNativeStreaming: !!(tizen && webapis),
      supportsNativeAudio: !!(tizen && webapis)
    };
  }

  function registerKeys(keys) {
    var tizen = getTizen();
    var requested = Array.isArray(keys) ? keys : DEFAULT_KEYS;
    var registered = [];
    var failed = [];
    requested.forEach(function(key) {
      try {
        if (!tizen || !tizen.tvinputdevice || typeof tizen.tvinputdevice.registerKey !== 'function') {
          throw new Error('Tizen TV input API is unavailable.');
        }
        tizen.tvinputdevice.registerKey(key);
        registered.push(key);
      } catch (error) {
        failed.push({ key: key, error: error && error.message ? error.message : String(error) });
      }
    });
    return { available: !!(tizen && tizen.tvinputdevice), registered: registered, failed: failed };
  }

  function setVolume(action) {
    var tizen = getTizen();
    var audio = tizen && tizen.tvaudiocontrol;
    if (!audio) {
      return false;
    }
    try {
      if (action === 'up' && typeof audio.setVolumeUp === 'function') {
        audio.setVolumeUp();
      } else if (action === 'down' && typeof audio.setVolumeDown === 'function') {
        audio.setVolumeDown();
      } else if (action === 'mute' && typeof audio.setMute === 'function') {
        var muted = typeof audio.isMute === 'function' ? !!audio.isMute() : false;
        audio.setMute(!muted);
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  function restartApp() {
    root.location.reload();
    return true;
  }

  function exitApp() {
    var tizen = getTizen();
    try {
      if (tizen && tizen.application && typeof tizen.application.getCurrentApplication === 'function') {
        tizen.application.getCurrentApplication().exit();
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  function getIpAddress() {
    return String(safeRead(function() {
      var webapis = getWebApis();
      return webapis && webapis.network && webapis.network.getIp();
    }, '') || '');
  }

  function openFile(path, mode) {
    var tizen = getTizen();
    if (!tizen || !tizen.filesystem || typeof tizen.filesystem.openFile !== 'function') {
      throw new Error('Tizen filesystem is unavailable.');
    }
    return tizen.filesystem.openFile(path, mode);
  }

  function closeFile(handle) {
    if (handle && typeof handle.close === 'function') {
      handle.close();
    }
  }

  function writeTextFile(path, text) {
    return Promise.resolve().then(function() {
      var handle = openFile(path, 'w');
      try {
        if (typeof handle.writeString === 'function') {
          handle.writeString(String(text));
        } else if (typeof handle.writeData === 'function' && typeof TextEncoder !== 'undefined') {
          handle.writeData(new TextEncoder().encode(String(text)));
        } else {
          throw new Error('This Tizen filesystem API cannot write text.');
        }
      } finally {
        closeFile(handle);
      }
      return path;
    });
  }

  function readTextFile(path) {
    return Promise.resolve().then(function() {
      var handle = openFile(path, 'r');
      try {
        if (typeof handle.readString !== 'function') {
          throw new Error('This Tizen filesystem API cannot read text.');
        }
        return handle.readString() || '';
      } finally {
        closeFile(handle);
      }
    });
  }

  function fileUri(path) {
    var tizen = getTizen();
    return safeRead(function() {
      return tizen && tizen.filesystem && typeof tizen.filesystem.toURI === 'function'
        ? tizen.filesystem.toURI(path)
        : path;
    }, path);
  }

  function launchAppControl(operation, uri, mimeType, subject, text) {
    return new Promise(function(resolve, reject) {
      var tizen = getTizen();
      if (!tizen || !tizen.application || !tizen.ApplicationControl) {
        reject(new Error('Tizen sharing is unavailable.'));
        return;
      }
      try {
        var data = [];
        if (tizen.ApplicationControlData) {
          if (subject) {
            data.push(new tizen.ApplicationControlData(
              'http://tizen.org/appcontrol/data/subject', [String(subject)]
            ));
          }
          if (text) {
            data.push(new tizen.ApplicationControlData(
              'http://tizen.org/appcontrol/data/text', [String(text)]
            ));
          }
        }
        var control = new tizen.ApplicationControl(operation, uri || null, mimeType || null, null, data);
        tizen.application.launchAppControl(control, null, resolve, reject);
      } catch (error) {
        reject(error);
      }
    });
  }

  function shareText(subject, text) {
    return launchAppControl(
      'http://tizen.org/appcontrol/operation/share',
      null,
      'text/plain',
      subject,
      text
    );
  }

  function shareFile(path, mimeType, subject) {
    return launchAppControl(
      'http://tizen.org/appcontrol/operation/share',
      fileUri(path),
      mimeType || 'application/octet-stream',
      subject,
      ''
    );
  }

  root.MoonlightTizenPlatform = Object.freeze({
    isTizen: function() { return !!getTizen(); },
    getPlatformInfo: getPlatformInfo,
    registerKeys: registerKeys,
    setVolume: setVolume,
    restartApp: restartApp,
    exitApp: exitApp,
    getIpAddress: getIpAddress,
    writeTextFile: writeTextFile,
    readTextFile: readTextFile,
    fileUri: fileUri,
    shareText: shareText,
    shareFile: shareFile,
    defaultKeys: DEFAULT_KEYS.slice()
  });
})(window);
