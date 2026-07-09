---
name: tizen-emulator-deploy
description: Build, sign, install, launch, and debug Moonlight Tizen WGTs with the VS Code Tizen extension TV emulator. Use when Codex needs to package patched wasm/platform files, use Samsung certificates from .env, handle tz/sdb CLI quirks, deploy to emulator-26101, run MoonLightS, or investigate emulator startup/loading behavior.
---

# Tizen Emulator Deploy

Use this workflow for Moonlight Tizen TV emulator packaging and deployment from this repo on Windows.

## Ground Rules

- Treat `.env`, `.p12`, `.pwd`, and certificate profile files as secrets. Never print password values.
- `.env` has contained `CERTNAME`, `CERTPASSWORD`, `CERTNAME2`, and `CERTPASSWORD2`; the Samsung cert has used the `*2` values.
- Use PowerShell path quoting with `& "path\to\tool.exe"` for Tizen tools.
- If `git` reports dubious ownership, inspect with `git -c safe.directory=C:/Dev/moonlight-tizen ...` rather than changing global config.
- Keep generated WGTs, password files, and unpacked widgets under ignored `build/codex-tizen-run/`.

## Tool Paths

The VS Code Tizen extension installs the usable CLI tools here:

```powershell
$SdkTools = Join-Path $env:USERPROFILE '.tizen-extension-platform\server\sdktools\data\tools'
$Sdb = Join-Path $SdkTools 'sdb.exe'
$Tz = Join-Path $SdkTools 'tizen-core\tz.exe'
```

The currently observed TV emulator:

```powershell
$Serial = 'emulator-26101'
$PackageId = 'MoonLightS'
$AppId = 'MoonLightS.MoonlightWasm'
```

Confirm before deploying:

```powershell
& $Sdb devices
& $Sdb -s $Serial capability
& $Sdb -s $Serial shell 0 getduid
& $Sdb -s $Serial shell 0 applist | Select-String -Pattern 'Moon'
```

Observed emulator facts:

- Device name: `T-samsung-10.0-x86_64`
- DUID: `XTCJYJZXZBZVK`
- `log_enable:disabled`, so `sdb dlog` is not useful.
- `intershell_support:disabled`, so normal interactive shell commands usually return no output.
- Secure commands like `shell 0 applist`, `shell 0 getduid`, and `shell 0 app_launcher` can work.
- `tz run --debug-mode` has still launched with `debug 0` and no forwarded inspector port.

## Samsung MCP Tools First

When the Samsung Tizen MCP servers are available in Codex, use them before manual `tz`, `sdb`, CDP, or debug-bridge work.

Current expected servers:

- `tizen-doctor-mcp`: use for `validate_environment`, `get_available_ides_info`, `launch_emulator`, `discover_devices`, `connect_tv_target`, `build_project`, `install_app`, `launch_app`, and `uninstall_app`.
- `tizen-simulator-mcp`: use for `start_simulator`, `stop_simulator`, `install_app`, `launch_app`, `list_apps`, `uninstall_app`, `get_simulator_info`, `remote_press`, `open_devtools`, `toggle_fullscreen`, and `minimize_window`.

Example user-facing prompts:

```text
Use tizen-doctor-mcp.validate_environment for this repo and summarize missing Tizen prerequisites.
```

```text
Use tizen-doctor-mcp.discover_devices, then install and launch build\codex-tizen-run\Moonlight-patched-scott-samsung.wgt on the active emulator.
```

```text
Use tizen-simulator-mcp.start_simulator, install the Moonlight WGT, list_apps to confirm the app ID, and launch the app.
```

```text
Use tizen-simulator-mcp.remote_press for enter, back, left, right, up, and down on the running app.
```

```text
Use tizen-simulator-mcp.get_simulator_info and open_devtools for the running simulator.
```

Use manual CLI commands only when the MCP server is unavailable, returns an insufficient error, or lacks the exact operation needed. Use the debug bridge only when MCP tools do not expose app-internal Moonlight state such as logs, `getState`, local storage, or Add Host form automation.

## Remote Debug Bridge

When MCP tools do not expose the app-internal state needed, use the app's dev-only HTTP polling bridge before spending time on `dlog` or manual emulator input. The tracked app config at `wasm/platform/debug_bridge_config.js` is disabled by default. Only enable it in ignored staged build output.

Start the local server on a LAN address the emulator can reach. Do not use `localhost` in the app config:

```powershell
$HostIp = '192.168.50.2'
$Token = '<local-debug-token>'
node tools/debug-bridge-server.mjs `
  --host 0.0.0.0 `
  --port 49321 `
  --token $Token `
  --public-url "http://${HostIp}:49321" `
  --write-config build\codex-tizen-run\debug_bridge_config.js
```

Overlay the generated config into the staged widget before creating the unsigned WGT:

```powershell
Copy-Item -Path wasm/index.html -Destination build/codex-tizen-run/patched-widget/index.html -Force
Copy-Item -Path wasm/platform/debug_bridge.js -Destination build/codex-tizen-run/patched-widget/platform/debug_bridge.js -Force
Copy-Item -Path build/codex-tizen-run/debug_bridge_config.js -Destination build/codex-tizen-run/patched-widget/platform/debug_bridge_config.js -Force
```

Use REST calls with the shared token to inspect and drive the app:

```powershell
$Headers = @{ 'X-Debug-Token' = $Token }
Invoke-RestMethod -Headers $Headers -Uri 'http://127.0.0.1:49321/api/clients'
Invoke-RestMethod -Headers $Headers -Uri 'http://127.0.0.1:49321/api/logs?tail=200'

$ClientId = '<client-id-from-api-clients>'
Invoke-RestMethod -Headers $Headers -Method Post -ContentType 'application/json' `
  -Uri 'http://127.0.0.1:49321/api/commands' `
  -Body (@{ clientId = $ClientId; type = 'getState'; args = @{} } | ConvertTo-Json -Depth 4)

Invoke-RestMethod -Headers $Headers -Method Post -ContentType 'application/json' `
  -Uri 'http://127.0.0.1:49321/api/commands' `
  -Body (@{ clientId = $ClientId; type = 'addHost'; args = @{ address = '192.168.50.2:46665' } } | ConvertTo-Json -Depth 4)

Invoke-RestMethod -Headers $Headers -Uri "http://127.0.0.1:49321/api/results?tail=20&clientId=$ClientId"
```

Allowed app commands are `nav`, `click`, `setValue`, `addHost`, `getState`, `localStorage`, and `reload`. There is no arbitrary JavaScript eval command. Keep tokens and enabled configs out of committed artifacts.

## VS Code Extension DevTools

Prefer `tizen-simulator-mcp.open_devtools` for simulator DevTools. When the VS Code Tizen extension starts a web debug session, it opens a Chrome DevTools window for the running app. That Chrome window is backed by a local Chrome DevTools Protocol endpoint, so Codex can attach directly while the session is open. The observed frontend looked like:

```text
http://127.0.0.1:35276/devtools/inspector.html?ws=127.0.0.1:35276/devtools/page/<target-id>
```

Do not hard-code the port; it changes per session. Discover it from the Chrome process command line:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq 'chrome.exe' -and $_.CommandLine -like '*devtools/inspector.html?ws=*' } |
  Select-Object ProcessId,CommandLine
```

Then query targets:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:<port>/json/list'
Invoke-RestMethod -Uri 'http://127.0.0.1:<port>/json/version'
```

Use the `webSocketDebuggerUrl` for the `Moonlight Game Streaming` page target. CDP can inspect DOM/state, read console/runtime events, evaluate targeted JavaScript, capture screenshots, and drive interactions. This is separate from `tz run --debug-mode`, which has been unreliable for opening a forwarded inspector port.

## Package Staging

If no local Emscripten/Docker build is available, stage from an existing WGT under `build/codex-tizen-run/patched-widget` and overlay the patched web files:

```powershell
Copy-Item -Path wasm/index.html -Destination build/codex-tizen-run/patched-widget/index.html -Force
Copy-Item -Path wasm/platform/debug_bridge_config.js -Destination build/codex-tizen-run/patched-widget/platform/debug_bridge_config.js -Force
Copy-Item -Path wasm/platform/debug_bridge.js -Destination build/codex-tizen-run/patched-widget/platform/debug_bridge.js -Force
Copy-Item -Path wasm/platform/index.js -Destination build/codex-tizen-run/patched-widget/platform/index.js -Force
Copy-Item -Path wasm/platform/audio.js -Destination build/codex-tizen-run/patched-widget/platform/audio.js -Force
```

Create an unsigned WGT directly from the staging directory. Exclude generated build outputs and old signatures:

```powershell
$root = (Resolve-Path 'build\codex-tizen-run\patched-widget').Path
$out = Join-Path (Resolve-Path 'build\codex-tizen-run').Path 'Moonlight-patched-unsigned.wgt'
$workspace = (Resolve-Path '.').Path
if (-not $root.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected staging root: $root" }
if (-not $out.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected output path: $out" }
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
    if ($rel -like 'Debug/*' -or $rel -eq 'tizen_web_project.yaml' -or $rel -eq 'author-signature.xml' -or $rel -eq 'signature1.xml') { return }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}
```

Sanity-check the package before signing:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path 'build\codex-tizen-run\Moonlight-patched-unsigned.wgt').Path)
try {
  $entries = $zip.Entries | Select-Object -ExpandProperty FullName
  [pscustomobject]@{
    HasConfig = $entries -contains 'config.xml'
    HasIndex = $entries -contains 'platform/index.js'
    HasAudio = $entries -contains 'platform/audio.js'
    HasWasm = $entries -contains 'moonlight-wasm.wasm'
    DebugEntries = @($entries | Where-Object { $_ -like 'Debug/*' -or $_ -like 'Debug\*' }).Count
  }
} finally {
  $zip.Dispose()
}
```

## Signing

Do not rely on direct project-folder signing for this repo:

```powershell
& $Tz pack --type wgt build\codex-tizen-run\patched-widget
```

That mode uses the active global profile, can ignore `--profiles-path`, and has failed with `ERROR:Decryption error!` for SDK-stored `.pwd` files.

Preferred signing path: repack the unsigned WGT with an explicit Samsung profile:

```powershell
& $Tz pack --type wgt `
  --base-pkg build\codex-tizen-run\Moonlight-patched-unsigned.wgt `
  --out-path build\codex-tizen-run\Moonlight-patched-scott-samsung.wgt `
  --sign-profile Scott-Samsung `
  --profiles-path build\codex-tizen-run\profiles-scott-samsung-local-pwd.xml
```

Known Samsung cert locations:

```text
C:\Users\ScottM\SamsungCertificate\Scott-Samsung\author.p12
C:\Users\ScottM\SamsungCertificate\Scott-Samsung\distributor.p12
```

If `profiles-scott-samsung-local-pwd.xml` is missing or stale, recreate a scratch profile using the Samsung cert password from `.env`, without echoing the password. The successful profile points at the Samsung `author.p12` and `distributor.p12`, with workspace-local encrypted `.pwd` files under `build/codex-tizen-run/`.

## Install And Launch

Install the signed WGT:

```powershell
& $Tz install --package-path build\codex-tizen-run\Moonlight-patched-scott-samsung.wgt --serial $Serial
```

Launch using the package ID, not the full app ID:

```powershell
& $Tz run --package-id MoonLightS --serial $Serial
```

Notes:

- `tz run --package-id MoonLightS.MoonlightWasm` has failed; use `MoonLightS`.
- `tz install` may log an uninstall/install app id derived from the WGT filename. Verify with `applist`; the real app has appeared as `Moonlight` / `MoonLightS.MoonlightWasm`.

## Verification

Before packaging source edits:

```powershell
node --check wasm/platform/index.js
node --check wasm/platform/audio.js
node --check wasm/platform/debug_bridge.js
node --check wasm/platform/debug_bridge_config.js
node --check tools/debug-bridge-server.mjs
git -c safe.directory=C:/Dev/moonlight-tizen diff --check -- wasm/index.html wasm/platform/index.js wasm/platform/audio.js wasm/platform/debug_bridge.js wasm/platform/debug_bridge_config.js tools/debug-bridge-server.mjs .codex/skills/tizen-emulator-deploy/SKILL.md AGENTS.md .gitignore
```

After launch, prefer the Samsung MCP tools for install/launch status, simulator state, DevTools, and remote input. Use the Remote Debug Bridge for startup logs, `getState`, and input-sensitive flows such as Add Host when the MCP tools do not expose enough app-internal state. Visual verification is still useful; if Windows Computer Use is available, follow its own skill instructions first, then capture the `Tizen Emulator` window and verify the Moonlight UI reaches the expected screen.

For startup/loading failures, suspect top-level JavaScript exceptions before `common.js` appends `moonlight-wasm.js`. In this repo, unguarded `tizen`/`webapis` platform probes in `wasm/platform/index.js` were enough to leave the emulator stuck on loading.
