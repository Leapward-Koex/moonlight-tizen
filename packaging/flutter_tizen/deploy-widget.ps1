[CmdletBinding()]
param(
    [string] $Package = 'build/flutter-tizen/MoonlightFlutter.wgt',
    [string] $Serial = 'emulator-26101',
    [string] $PackageId = 'MLFlutter1',
    [switch] $InstallOnly,
    [string] $TzPath = "$env:USERPROFILE/.tizen-extension-platform/server/sdktools/data/tools/tizen-core/tz.exe"
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$packagePath = if ([IO.Path]::IsPathRooted($Package)) {
    [IO.Path]::GetFullPath($Package)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $Package))
}
if (-not $packagePath.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package must remain inside the workspace: $packagePath"
}
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Signed WGT not found: $packagePath"
}

$tz = [IO.Path]::GetFullPath($TzPath)
if (-not (Test-Path -LiteralPath $tz -PathType Leaf)) {
    throw "Tizen extension CLI not found: $tz"
}

& $tz install --package-path $packagePath --serial $Serial
if ($LASTEXITCODE -ne 0) {
    throw "Tizen install failed with exit code $LASTEXITCODE."
}

if (-not $InstallOnly) {
    & $tz run --package-id $PackageId --serial $Serial
    if ($LASTEXITCODE -ne 0) {
        throw "Tizen launch failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Deployed $packagePath to $Serial"
Write-Host "Package ID: $PackageId"
