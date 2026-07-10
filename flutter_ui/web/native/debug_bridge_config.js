(function() {
  'use strict';

  var config = {
    enabled: false,
    serverUrl: '',
    token: '',
    clientName: 'moonlight-flutter'
  };

  try {
    var text = window.localStorage && window.localStorage.getItem('moonlightDebugBridgeConfig');
    if (text) {
      var override = JSON.parse(text);
      config.enabled = override.enabled === true;
      config.serverUrl = override.serverUrl ? String(override.serverUrl) : '';
      config.token = override.token ? String(override.token) : '';
      config.clientName = override.clientName ? String(override.clientName) : config.clientName;
    }
  } catch (error) {
    config.enabled = false;
    config.serverUrl = '';
    config.token = '';
  }

  window.MOONLIGHT_DEBUG_BRIDGE = window.MOONLIGHT_DEBUG_BRIDGE || config;
})();
