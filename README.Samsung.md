# Moonlight port for Samsung Smart TVs running Tizen OS

This is a fork of the `Moonlight Chrome` project adapted to run on Samsung Tizen TVs.
Changes made:

- WebAssembly is used instead of Native Client
- Main adaptation layer is in a wasm/ directory instead of the root project directory

## Used Tizen specific features

- [Tizen WASM Player](https://developer.samsung.com/smarttv/develop/extension-libraries/webassembly/tizen-wasm-player/overview.html)
- [Tizen Sockets Extension](https://developer.samsung.com/smarttv/develop/extension-libraries/webassembly/api-reference/tizen-sockets-extension.html)

## Checking out required submodules
Since some of the dependencies used are provided as git submodules, after cloning this repository (if you did not provide the `--recurse-submodules` option while cloning) you need to issue the below command:

```bash
git submodule update --init --recursive
```

## Building

### Required software
- [Samsung Emscripten fork](https://developer.samsung.com/smarttv/develop/extension-libraries/webassembly/getting-started/downloading-and-installing.html)
- cmake (at least 3.10 - tested using CMake 3.10 and CMake 3.18)
- ninja (at least 1.8.2- recommended for Windows)

### Build procedure

```bash
mkdir build
cd build/
cmake -DCMAKE_TOOLCHAIN_FILE=<YOUR EMSCRIPTEN INSTALLATION_DIR>/cmake/Modules/Platform/Emscripten.cmake -G Ninja ..
ninja

# CMake 3.10 (and above):
cmake -DCMAKE_INSTALL_PREFIX=. -P cmake_install.cmake

# CMake 3.15 (and above):
cmake --install . --prefix .
```

*Note:* On Linux and macOS you can also use `Makefile` cmake generators.

After that you can pack widget as described in [Sample cURL application built using CLI tools](https://developer.samsung.com/smarttv/develop/extension-libraries/webassembly/tizen-sockets-extension/sample-curl-application-built-using-cli-tools.html) tutorial.

### VS Code Tizen extension

The Tizen web project root is `wasm/`. Use that folder for the extension's Run/Debug actions, not `res/`.

Before running from the extension, copy the generated Emscripten runtime files into the web project:

```powershell
powershell -ExecutionPolicy Bypass -File tools/sync-tizen-extension-project.ps1
```

The script copies `moonlight-wasm.js`, `moonlight-wasm.js.mem`, `moonlight-wasm.wasm`, and `moonlight-wasm.worker.js` from `build/widget` or `build/codex-tizen-run/patched-widget` into `wasm/`. Those generated files are intentionally ignored by git.

### MCP-first debug workflow

Use the Samsung Tizen MCP servers from Codex before manual `sdb`, Chrome DevTools Protocol, or debug-bridge work. This repo expects the non-Flutter servers:

- `tizen-doctor-mcp`: environment validation, IDE information, emulator launch, device discovery, project build, app install/launch/uninstall, and TV target connection.
- `tizen-simulator-mcp`: TV Web Simulator start/stop, app install/list/launch/uninstall, remote key presses, simulator info, window/fullscreen controls, and DevTools opening.

Useful Codex prompts:

```text
Use tizen-doctor-mcp.validate_environment for this repo and report anything missing.
```

```text
Use tizen-doctor-mcp.discover_devices, then install and launch the current Moonlight WGT on the active emulator.
```

```text
Use tizen-simulator-mcp.start_simulator, install the app from build\codex-tizen-run\MoonlightWasm.wgt, list_apps to confirm the app ID, and launch it.
```

```text
Use tizen-simulator-mcp.remote_press to send enter, back, left, right, up, and down to the running app.
```

```text
Use tizen-simulator-mcp.get_simulator_info and open_devtools for the running simulator.
```

Prefer the MCPs for routine environment, install, launch, simulator, and remote-control work. Use the debug bridge or direct DevTools attachment only when the MCP tools cannot expose the app-internal state you need, such as Moonlight runtime logs, `getState`, local storage, or Add Host form automation.

### Debug bridge fallback

For a local debug-bridge build, use the same sync step with `-EnableDebugBridge` before starting the Tizen extension debug action:

```powershell
powershell -ExecutionPolicy Bypass -File tools/sync-tizen-extension-project.ps1 -EnableDebugBridge -DebugBridgeHostIp 192.168.50.2
```

This writes an enabled `wasm/platform/debug_bridge_config.js` with a local token stored under ignored `build/codex-tizen-run/`. If your host IP differs, pass `-DebugBridgeHostIp` or `-DebugBridgeServerUrl`. Start the bridge server with the same token before launching the app:

```powershell
$Token = (Get-Content -Raw build\codex-tizen-run\debug_bridge_token.txt).Trim()
node tools/debug-bridge-server.mjs --host 0.0.0.0 --port 49321 --token $Token --public-url "http://192.168.50.2:49321"
```

Before committing, restore the disabled checked-in config:

```powershell
powershell -ExecutionPolicy Bypass -File tools/write-debug-bridge-config.ps1 -Disable
```

If the extension says `Library projects without tizen-manifest.xml cannot be launched`, set the Tizen working project to the `wasm/` folder. In VS Code, right-click `wasm/` and choose **Tizen: Set as Working Project**, or set `tizen.v2.working.project` to the absolute path of this repository's `wasm/` folder.

### DevTools fallback

The `tizen-simulator-mcp.open_devtools` tool is the preferred way to open simulator DevTools. If you launched from the VS Code Tizen extension instead, the extension opens a Chrome DevTools window for the running app. The window is backed by a local Chrome DevTools Protocol endpoint, so automation tools can inspect the DOM, read console output, evaluate JavaScript, and drive the app while the debug session is open.

The port changes per session. On Windows, discover the current endpoint from the Chrome process command line:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq 'chrome.exe' -and $_.CommandLine -like '*devtools/inspector.html?ws=*' } |
  Select-Object ProcessId,CommandLine
```

The command line contains a URL like `http://127.0.0.1:<port>/devtools/inspector.html?ws=127.0.0.1:<port>/devtools/page/<target-id>`. Use that port to list attachable targets:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:<port>/json/list'
```

The Moonlight target should have title `Moonlight Game Streaming` and a `webSocketDebuggerUrl` value. Attach to that WebSocket URL with any CDP client.
