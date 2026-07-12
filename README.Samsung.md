# Legacy Moonlight Tizen widget

This document covers the legacy DOM application in `wasm/` (package ID
`MoonLightS`). The current Flutter preview uses package ID `MLFlutter1`; its
verified local workflow is documented in [`DEVELOPMENT.md`](DEVELOPMENT.md).

The legacy port depends on Samsung's Emscripten fork, Tizen WASM Player, and
Tizen Sockets Extension. Initialize submodules before configuring a new tree:

```powershell
git submodule update --init --recursive
```

## Build

For an existing Ninja tree, follow the workspace-local Emscripten environment
documented in `AGENTS.override.md`, then build `moonlight-wasm`. These overrides
avoid a stale upstream Tizen OpenSSL port URL and intentionally remain outside
source control.

For a new tree, configure CMake and Ninja with Samsung's Emscripten toolchain,
then install to a widget staging directory. Upstream Emscripten does not provide
the required Tizen socket/player runtime.

## VS Code Tizen extension

The working Tizen web project is `wasm/`, not `res/` or the repository root.
Sync the generated runtime files before using the extension's Run/Debug action:

```powershell
.\tools\sync-tizen-extension-project.ps1
```

If the extension reports `Library projects without tizen-manifest.xml cannot be
launched`, right-click `wasm/` and select **Tizen: Set as Working Project**, or
set `tizen.v2.working.project` to the absolute `wasm/` directory.

For an authenticated bridge run:

```powershell
.\tools\sync-tizen-extension-project.ps1 `
  -EnableDebugBridge -DebugBridgeHostIp <host-ip>

$Token = (Get-Content -Raw build\codex-tizen-run\debug_bridge_token.txt).Trim()
node tools\debug-bridge-server.mjs `
  --host 0.0.0.0 --port 49321 --token $Token `
  --public-url 'http://<host-ip>:49321'
```

Use the modern Node executable and emulator-reachable host address documented
in the machine-local override. Never use `localhost` in app-side configuration.
Restore the checked-in disabled configuration after an extension run:

```powershell
.\tools\write-debug-bridge-config.ps1 -Disable -ProjectRoot wasm
```

## Install and launch

Install a signed legacy WGT using the VS Code Tizen extension CLI, then launch
package ID `MoonLightS`, not full application ID
`MoonLightS.MoonlightWasm`. Generated WGTs, signing profiles, passwords, and
tokens must remain under ignored `build/` directories.

For emulator limitations, REST bridge commands, signing guidance, and the
current Flutter workflow, see [`DEVELOPMENT.md`](DEVELOPMENT.md).
