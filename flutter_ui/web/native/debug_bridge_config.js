(function() {
  'use strict';

  var config = {
    enabled: false,
    serverUrl: '',
    token: '',
    clientName: 'moonlight-flutter'
  };

  window.MOONLIGHT_DEBUG_BRIDGE = window.MOONLIGHT_DEBUG_BRIDGE || config;
})();
