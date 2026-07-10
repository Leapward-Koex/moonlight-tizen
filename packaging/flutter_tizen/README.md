# Moonlight Flutter Tizen packaging

This project uses an identity separate from the legacy widget so both can be installed together:

- package: `MLFlutter1`
- application: `MLFlutter1.MoonlightFlutter`
- widget: `http://samsung.tv/MoonlightFlutter`
- minimum platform: Tizen 10.0

Build the Flutter app with local CanvasKit and no service worker, then stage it with the existing native runtime:

```powershell
flutter build web --release -t lib/main.dart --csp --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none
./packaging/flutter_tizen/stage-widget.ps1
```

Pass `-ForceGameMode` to stage the Samsung Game Mode metadata variant. The staging script only assembles a directory under `build/flutter-tizen/widget`; signing profiles, passwords, signatures, and generated WGTs remain outside source control.

Create an unsigned WGT, or sign it with an explicit workspace-local profile:

```powershell
./packaging/flutter_tizen/package-widget.ps1
./packaging/flutter_tizen/package-widget.ps1 -Sign
```

Build the Force Game Mode artifact separately so it can be installed in place of the standard Flutter preview:

```powershell
./packaging/flutter_tizen/stage-widget.ps1 `
  -Output build/flutter-tizen/widget-force-game-mode -ForceGameMode
./packaging/flutter_tizen/package-widget.ps1 `
  -Stage build/flutter-tizen/widget-force-game-mode `
  -Output build/flutter-tizen/MoonlightFlutter-ForceGM.wgt -Sign
```

The final artifact names are `MoonlightFlutter.wgt` and `MoonlightFlutter-ForceGM.wgt`. Launch either variant with package ID `MLFlutter1`.

Release packages contain the remote diagnostics bridge in a disabled state.
For an emulator or explicitly controlled test device, start
`tools/debug-bridge-server.mjs` with a modern Node version and use
`--write-config build/flutter-tizen/widget/native/debug_bridge_config.js`
before signing that staged widget. Set `--public-url` to a host address the TV
can reach (the current emulator uses `http://192.168.50.2:49321`, not
`localhost`). The generated config contains an access token and must remain in
ignored build output.
