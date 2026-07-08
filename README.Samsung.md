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

If the extension says `Library projects without tizen-manifest.xml cannot be launched`, set the Tizen working project to the `wasm/` folder. In VS Code, right-click `wasm/` and choose **Tizen: Set as Working Project**, or set `tizen.v2.working.project` to the absolute path of this repository's `wasm/` folder.

When the extension starts a debug session, it opens a Chrome DevTools window for the running app. The window is backed by a local Chrome DevTools Protocol endpoint, so automation tools can inspect the DOM, read console output, evaluate JavaScript, and drive the app while the debug session is open.

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
