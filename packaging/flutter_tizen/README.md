# Moonlight Flutter Tizen packaging

The Flutter Tizen app uses this identity:

- package: `MLFlutter1`
- application: `MLFlutter1.MoonlightFlutter`
- widget: `http://samsung.tv/MoonlightFlutter`
- minimum platform: Tizen 10.0

For the complete workstation workflow and troubleshooting, read
[`DEVELOPMENT.md`](../../DEVELOPMENT.md). The normal build/sign/install/launch
command is:

```powershell
.\packaging\flutter_tizen\build-emulator.ps1
```

To run the phases separately:

```powershell
# After building wasm and flutter_ui/build/web:
.\packaging\flutter_tizen\stage-widget.ps1
.\packaging\flutter_tizen\package-widget.ps1 -Sign
.\packaging\flutter_tizen\deploy-widget.ps1
```

All three commands agree on `build/flutter-tizen/widget-standard` and
`build/flutter-tizen/MoonlightFlutter.wgt`. Use `-ForceGameMode` with the build
or staging command for the alternate manifest. Staging validates the Flutter
shell, native bridge, WebAssembly artifacts, and isolated Tizen identity.

Signing always uses an explicit profile file outside source control. Generated
WGTs, signatures, tokens, and password files belong under ignored `build/`
directories.

For emulator-only remote diagnostics, pass `-EnableDebugBridge` to the combined
script, or configure an already staged widget:

```powershell
.\tools\write-debug-bridge-config.ps1 -Enable `
  -ProjectRoot build\flutter-tizen\widget-standard `
  -HostIp <emulator-reachable-host-ip>
```

Then sign/deploy that stage and start `tools/debug-bridge-server.mjs` with the
same token using modern Node. Never ship an enabled bridge configuration.
