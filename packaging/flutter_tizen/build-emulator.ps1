[CmdletBinding()]
param(
    [switch] $SkipWasm,
    [switch] $SkipFlutter,
    [switch] $ForceGameMode,
    [switch] $EnableDebugBridge,
    [string] $DebugBridgeHostIp = $env:MOONLIGHT_DEBUG_BRIDGE_HOST_IP,
    [string] $Serial = 'emulator-26101',
    [switch] $NoDeploy,
    [string] $FlutterPath = '',
    [string] $SignProfile = $env:MOONLIGHT_TIZEN_SIGN_PROFILE,
    [string] $ProfilesPath = $env:MOONLIGHT_TIZEN_PROFILES_PATH
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wasmBuild = Join-Path $workspace 'build\codex-wasm-proxy-pthread'
$stage = Join-Path $workspace $(if ($ForceGameMode) { 'build\flutter-tizen\widget-force-game-mode' } else { 'build\flutter-tizen\widget-standard' })
$package = Join-Path $workspace $(if ($ForceGameMode) { 'build\flutter-tizen\MoonlightFlutter-ForceGM.wgt' } else { 'build\flutter-tizen\MoonlightFlutter.wgt' })

if (-not $SkipWasm) {
    $env:EM_CACHE = Join-Path $workspace 'build\codex-em-cache'
    $env:EM_CONFIG = Join-Path $workspace 'build\codex-emscripten-local.config'
    $env:EM_PORTS = Join-Path $workspace 'build\codex-em-ports'
    & cmake --build $wasmBuild --target moonlight-wasm
    if ($LASTEXITCODE -ne 0) { throw "WebAssembly build failed with exit code $LASTEXITCODE." }
}

if (-not $SkipFlutter) {
    if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
        $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
        if ($null -eq $flutterCommand) {
            throw 'Flutter is not on PATH. Re-run with -FlutterPath <path-to-flutter>.'
        }
        $FlutterPath = $flutterCommand.Source
    }
    if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
        throw "Flutter executable not found: $FlutterPath"
    }
    $env:DART_ANALYTICS_DISABLED = 'true'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    Push-Location (Join-Path $workspace 'flutter_ui')
    try {
        & $FlutterPath build web --release -t lib/main.dart --csp --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none
        if ($LASTEXITCODE -ne 0) { throw "Flutter web build failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

& (Join-Path $PSScriptRoot 'stage-widget.ps1') -Output $stage -ForceGameMode:$ForceGameMode
if ($EnableDebugBridge) {
    $bridgeArgs = @{ Enable = $true; ProjectRoot = $stage }
    if (-not [string]::IsNullOrWhiteSpace($DebugBridgeHostIp)) {
        $bridgeArgs.HostIp = $DebugBridgeHostIp
    }
    & (Join-Path $workspace 'tools\write-debug-bridge-config.ps1') @bridgeArgs
}
& (Join-Path $PSScriptRoot 'package-widget.ps1') -Stage $stage -Output $package `
    -Sign -SignProfile $SignProfile -ProfilesPath $ProfilesPath

if (-not $NoDeploy) {
    & (Join-Path $PSScriptRoot 'deploy-widget.ps1') -Package $package -Serial $Serial
}

Write-Host "Moonlight Flutter emulator workflow completed."
Write-Host "Package: $package"
if ($EnableDebugBridge) {
    Write-Host 'Debug bridge config enabled in the staged widget.'
}
