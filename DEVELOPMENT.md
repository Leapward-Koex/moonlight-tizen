# Local build and Tizen emulator workflow

This is the canonical local workflow for the Flutter Tizen app. It builds the
Moonlight WebAssembly runtime, builds Flutter Web, stages a complete widget,
signs it with the local Samsung profile, installs it, and launches it on the TV
emulator.

## Fast path on this workstation

Start the Tizen 10 TV emulator, then run from the repository root:

```powershell
.\packaging\flutter_tizen\build-emulator.ps1
```

## VS Code one-click build and launch

Start the Tizen TV emulator, open **Run and Debug**, select
**Moonlight: build + run on attached Tizen emulator**, and press F5 (or click
the green launch button). This performs the complete C++/WebAssembly and
Flutter/JavaScript build, stages and signs the WGT, installs it on the single
attached emulator, and launches package `MLFlutter1`.

The same workflow is the default VS Code build task, so Ctrl+Shift+B also runs
it. For Flutter/JavaScript-only changes, run the task
**moonlight: rebuild Flutter/JS + deploy (skip C++/Wasm)** to save the native
rebuild time.

On first use, the launcher reads the local Samsung certificate name and
password from `.env` and creates an ignored, per-Windows-user signing profile
under `build/codex-tizen-run/vscode-signing/`. This is necessary because
Tizen's encrypted `.pwd` files cannot be shared between Windows identities.
Existing setups can instead set both `MOONLIGHT_TIZEN_SIGN_PROFILE` and
`MOONLIGHT_TIZEN_PROFILES_PATH`. If multiple devices are attached, set
`MOONLIGHT_TIZEN_SERIAL` as well.

The script uses these stable local defaults:

- Emscripten tree: `build/codex-wasm-proxy-pthread`
- Flutter SDK: the `flutter` command selected by `PATH` (override with
  `-FlutterPath` when needed)
- staged widget: `build/flutter-tizen/widget-standard`
- signed WGT: `build/flutter-tizen/MoonlightFlutter.wgt`
- signing profile: supplied with `-SignProfile` and `-ProfilesPath` or the
  corresponding `MOONLIGHT_TIZEN_*` environment variables
- emulator: `emulator-26101`
- launch package ID: `MLFlutter1`

Use `-SkipWasm` or `-SkipFlutter` only when the corresponding output is known to
be current. Use `-NoDeploy` to stop after signing, and `-ForceGameMode` for the
alternate manifest.

In a restricted Codex session, use two phases: run the Flutter command from
section 2 with access to the installed SDK cache, then return to the normal
workspace context and run the fast path with `-SkipFlutter`. Do not sign in the
elevated Flutter context: locally encrypted Tizen `.pwd` files may fail there
with `ERROR:Decryption error!`.

## What the fast path runs

### 1. WebAssembly

The existing Ninja tree must use the workspace-local Emscripten cache, config,
and ports directories. These avoid the stale upstream Tizen OpenSSL port URL:

```powershell
$env:EM_CACHE="$PWD\build\codex-em-cache"
$env:EM_CONFIG="$PWD\build\codex-emscripten-local.config"
$env:EM_PORTS="$PWD\build\codex-em-ports"
cmake --build build\codex-wasm-proxy-pthread --target moonlight-wasm
```

Success produces `moonlight-wasm.js`, `.js.mem`, `.wasm`, and `.worker.js` in
`build/codex-wasm-proxy-pthread`.

### 2. Flutter Web

Run Flutter from `flutter_ui`:

```powershell
flutter build web --release `
  -t lib/main.dart --csp --no-web-resources-cdn `
  --no-wasm-dry-run --pwa-strategy=none
```

Success produces `flutter_ui/build/web/main.dart.js`. In a restricted agent
sandbox, Flutter can hang silently before printing `Compiling`, and even
`flutter --version` may hang because the SDK needs its global cache. Retry the
same command with permission to access the installed Flutter SDK/cache; the
normal build takes tens of seconds on this machine. Clean up only orphaned Dart
processes started by the failed attempt.

### 3. Stage, sign, deploy

```powershell
.\packaging\flutter_tizen\stage-widget.ps1
.\packaging\flutter_tizen\package-widget.ps1 -Sign
.\packaging\flutter_tizen\deploy-widget.ps1
```

The stage and package defaults both use `build/flutter-tizen/widget-standard`.
Signing repacks an unsigned WGT with an explicit workspace-local profile passed
through `-SignProfile` and `-ProfilesPath`; never print `.env` values or
certificate passwords. The real application ID is
`MLFlutter1.MoonlightFlutter`, but `tz run` requires package ID `MLFlutter1`.
Install output may temporarily derive an ID from the WGT filename; verify the
installed ID with `sdb shell 0 applist` when in doubt.

## Remote debug bridge

The bridge is authenticated, allowlisted, and disabled in source/release
builds. Enable it only in a staged emulator widget:

```powershell
.\tools\write-debug-bridge-config.ps1 -Enable `
  -ProjectRoot build\flutter-tizen\widget-standard `
  -HostIp <emulator-reachable-host-ip>

$Token = (Get-Content -Raw build\codex-tizen-run\debug_bridge_token.txt).Trim()
node tools\debug-bridge-server.mjs `
  --host 0.0.0.0 --port 49321 --token $Token `
  --public-url 'http://<emulator-reachable-host-ip>:49321'
```

Use a modern Node.js runtime; a machine-local override may be required when an
older runtime appears first on `PATH`. Do not use `localhost` in app-side
configuration because the emulator must reach the host over its network.

After enabling the bridge, sign and redeploy the staged widget. Query it from a
second PowerShell window without printing the token:

```powershell
$Headers = @{ 'X-Debug-Token' = $Token }
Invoke-RestMethod -Headers $Headers http://127.0.0.1:49321/api/health
Invoke-RestMethod -Headers $Headers http://127.0.0.1:49321/api/clients
Invoke-RestMethod -Headers $Headers 'http://127.0.0.1:49321/api/logs?tail=200'
```

Allowed commands include `getState`, `getDiagnostics`, `setLogLevel`,
`clearDiagnostics`, `nav`, `click`, `setValue`, `addHost`, `localStorage`, and
`reload`. Tokens and enabled configs must remain under ignored `build/` output.

## Emulator checks and troubleshooting

The VS Code Tizen extension tools are under
`$env:USERPROFILE\.tizen-extension-platform\server\sdktools\data\tools`.

```powershell
$Tools = Join-Path $env:USERPROFILE '.tizen-extension-platform\server\sdktools\data\tools'
& "$Tools\sdb.exe" devices
& "$Tools\sdb.exe" -s emulator-26101 capability
& "$Tools\sdb.exe" -s emulator-26101 shell 0 applist | Select-String Moonlight
```

This emulator has `log_enable:disabled` and `intershell_support:disabled`, so
`sdb dlog` and ordinary interactive shell commands are poor diagnostics. Prefer
the remote bridge for application state/logs. Secure commands such as
`shell 0 applist`, `getduid`, and `app_launcher` still work.
