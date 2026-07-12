# Moonlight Flutter UI

This is the side-by-side Flutter Web rewrite of Moonlight Tizen's legacy DOM
interface. It targets the Tizen 10 preview package `MLFlutter1` and leaves the
existing `MoonLightS` application unchanged.

## Development

Use Flutter 3.44.1. A machine-local agent override can document the selected
SDK when it is not already on `PATH`:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

Run the deterministic browser backend for UI development:

```powershell
flutter run -d chrome -t lib/main_fake.dart
```

The browser backend does not load the Samsung-specific Moonlight WASM runtime.
Real networking, audio, video, and stream input are available only in the Tizen
WGT, where the JavaScript bridge can access Samsung's socket and media APIs.

## Production build

The Tizen staging workflow builds JavaScript/CanvasKit locally, overlays the
Moonlight Emscripten artifacts, and adds the manifest from
`../packaging/flutter_tizen/`. Run the packaging script documented there; do
not package `build/web` directly because it lacks the native runtime and Tizen
metadata.

The real web shell deliberately retains a native
`<video id="wasm_module">` outside Flutter's render tree. The identifier and
element placement are part of the native ABI and must not be changed.

## Diagnostics

New installs log at `Info` by default. The logger captures Flutter framework and
Riverpod failures, native/WASM initialization, NvHTTP operations, pairing and
stream lifecycle, input/gamepad state transitions, and uncaught JavaScript
errors. It stores bounded NDJSON in Tizen private storage at
`wgt-private/logs/moonlight-flutter-log.ndjson` (10 MB maximum); the browser
backend uses a 1 MB `localStorage` fallback.

Use **Settings > Advanced > Diagnostic log storage** to change the level, view
storage health, clear logs, or export a redacted bundle. Device exports show a
short-lived same-LAN URL and QR code. PINs, keys, certificates, RTSP/session
URLs, and other known secrets are redacted before storage and export.

For bring-up work, the authenticated remote debug bridge can forward the same
redacted entries and run `getState` or `getDiagnostics` without navigating the
TV UI. It is included but disabled by default. Generate an enabled config only
in a staged debug WGT with `tools/debug-bridge-server.mjs --write-config`; never
commit its token or ship that generated config as a release package.
