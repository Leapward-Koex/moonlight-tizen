{{flutter_js}}
{{flutter_build_config}}

(function bootstrapMoonlightFlutter() {
  'use strict';

  var host = document.getElementById('flutter-host');
  if (!host) {
    throw new Error('Moonlight Flutter host element is missing.');
  }

  _flutter.loader.load({
    config: {
      renderer: 'canvaskit',
      canvasKitBaseUrl: 'canvaskit/',
      canvasKitVariant: 'full'
    },
    onEntrypointLoaded: function(engineInitializer) {
      engineInitializer.initializeEngine({
        hostElement: host
      }).then(function(appRunner) {
        return appRunner.runApp();
      }).catch(function(error) {
        host.dataset.bootstrapError = 'true';
        host.textContent = 'Unable to start Moonlight Flutter: ' +
          (error && error.message ? error.message : String(error));
        throw error;
      });
    }
  });
})();
