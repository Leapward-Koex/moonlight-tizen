(function() {
  'use strict';

  var config = {
    enabled: false,
    serverUrl: '',
    token: '',
    clientName: 'tizen-emulator'
  };

  try {
    var overrideText = window.localStorage && window.localStorage.getItem('moonlightDebugBridgeConfig');
    if (overrideText) {
      var override = JSON.parse(overrideText);
      if (override && typeof override === 'object') {
        config.enabled = override.enabled === true;
        config.serverUrl = override.serverUrl ? String(override.serverUrl) : '';
        config.token = override.token ? String(override.token) : '';
        config.clientName = override.clientName ? String(override.clientName) : config.clientName;
      }
    }
  } catch (error) {
    config.enabled = false;
    config.serverUrl = '';
    config.token = '';
  }

  window.MOONLIGHT_DEBUG_BRIDGE = window.MOONLIGHT_DEBUG_BRIDGE || config;
})();