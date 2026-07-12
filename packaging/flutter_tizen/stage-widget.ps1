[CmdletBinding()]
param(
    [string] $FlutterBuild = 'flutter_ui/build/web',
    [string] $WasmBuild = 'build/codex-wasm-proxy-pthread',
    [string] $Output = 'build/flutter-tizen/widget-standard',
    [switch] $ForceGameMode
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Resolve-WorkspacePath([string] $Path, [switch] $MustExist) {
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $workspace $Path))
    }
    if (-not $candidate.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the workspace: $candidate"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $candidate)) {
        throw "Required path does not exist: $candidate"
    }
    return $candidate
}

$flutterRoot = Resolve-WorkspacePath $FlutterBuild -MustExist
$wasmRoot = Resolve-WorkspacePath $WasmBuild -MustExist
$outputRoot = Resolve-WorkspacePath $Output

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

Copy-Item -Path (Join-Path $flutterRoot '*') -Destination $outputRoot -Recurse -Force

$configName = if ($ForceGameMode) { 'config.force-game-mode.xml' } else { 'config.xml' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $configName) -Destination (Join-Path $outputRoot 'config.xml') -Force

$runtimeArtifacts = @(
    'moonlight-wasm.js',
    'moonlight-wasm.js.mem',
    'moonlight-wasm.wasm',
    'moonlight-wasm.worker.js'
)
foreach ($artifact in $runtimeArtifacts) {
    $source = Join-Path $wasmRoot $artifact
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing native runtime artifact: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $outputRoot $artifact) -Force
}

$requiredFiles = @(
    'config.xml',
    'index.html',
    'flutter_bootstrap.js',
    'main.dart.js',
    'native/audio.js',
    'native/audio-worklet.js',
    'native/diagnostics.js',
    'native/debug_bridge_config.js',
    'native/debug_bridge.js',
    'native/input.js',
    'native/moonlight_native.js',
    'native/tizen_platform.js',
    'styles/native_surface.css'
) + $runtimeArtifacts
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $outputRoot $relativePath) -PathType Leaf)) {
        throw "Staged widget is missing required file: $relativePath"
    }
}

$indexText = Get-Content -LiteralPath (Join-Path $outputRoot 'index.html') -Raw
if ($indexText -notmatch '<video\s+id="wasm_module"\s+autoplay') {
    throw 'index.html must retain the permanent autoplay #wasm_module video element.'
}
$webApisIndex = $indexText.IndexOf('$WEBAPIS/webapis/webapis.js')
$nativeBridgeIndex = $indexText.IndexOf('native/moonlight_native.js')
if ($webApisIndex -lt 0 -or $nativeBridgeIndex -lt 0 -or $webApisIndex -gt $nativeBridgeIndex) {
    throw 'Samsung webapis.js must load before the Moonlight native bridge.'
}

[xml] $config = Get-Content -LiteralPath (Join-Path $outputRoot 'config.xml') -Raw
$ns = New-Object Xml.XmlNamespaceManager($config.NameTable)
$ns.AddNamespace('tizen', 'http://tizen.org/ns/widgets')
$application = $config.SelectSingleNode('//tizen:application', $ns)
if ($application.id -ne 'MLFlutter1.MoonlightFlutter' -or $application.package -ne 'MLFlutter1') {
    throw 'Staged Tizen identity is not the isolated Moonlight Flutter identity.'
}
if ($application.required_version -ne '10.0') {
    throw 'Moonlight Flutter preview must require Tizen 10.0.'
}

Write-Host "Staged Moonlight Flutter widget at $outputRoot"
Write-Host "Variant: $(if ($ForceGameMode) { 'Force Game Mode' } else { 'Standard' })"
