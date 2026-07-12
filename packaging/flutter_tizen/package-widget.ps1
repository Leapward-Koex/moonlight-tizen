[CmdletBinding()]
param(
    [string] $Stage = 'build/flutter-tizen/widget-standard',
    [string] $Output = 'build/flutter-tizen/MoonlightFlutter.wgt',
    [switch] $Sign,
    [string] $SignProfile = $env:MOONLIGHT_TIZEN_SIGN_PROFILE,
    [string] $ProfilesPath = $env:MOONLIGHT_TIZEN_PROFILES_PATH,
    [string] $TzPath = "$env:USERPROFILE/.tizen-extension-platform/server/sdktools/data/tools/tizen-core/tz.exe"
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

$stageRoot = Resolve-WorkspacePath $Stage -MustExist
$outputPath = Resolve-WorkspacePath $Output
if ([IO.Path]::GetExtension($outputPath) -ne '.wgt') {
    throw 'Output must use the .wgt extension.'
}
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$unsignedPath = if ($Sign) {
    Join-Path $outputDirectory (([IO.Path]::GetFileNameWithoutExtension($outputPath)) + '-unsigned.wgt')
} else {
    $outputPath
}
if (Test-Path -LiteralPath $unsignedPath) {
    Remove-Item -LiteralPath $unsignedPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($unsignedPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $stageRoot -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
        if ($relative -eq 'author-signature.xml' -or $relative -eq 'signature1.xml') {
            return
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $_.FullName,
            $relative,
            [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $zip.Dispose()
}

if ($Sign) {
    if ([string]::IsNullOrWhiteSpace($SignProfile)) {
        throw 'Signing profile is required. Pass -SignProfile or set MOONLIGHT_TIZEN_SIGN_PROFILE.'
    }
    if ([string]::IsNullOrWhiteSpace($ProfilesPath)) {
        throw 'Profiles path is required. Pass -ProfilesPath or set MOONLIGHT_TIZEN_PROFILES_PATH.'
    }
    $profiles = Resolve-WorkspacePath $ProfilesPath -MustExist
    $tz = [IO.Path]::GetFullPath($TzPath)
    if (-not (Test-Path -LiteralPath $tz -PathType Leaf)) {
        throw "Tizen extension CLI not found: $tz"
    }
    $signExitCode = 1
    foreach ($attempt in 1..2) {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }
        $signOutput = @(& $tz pack --type wgt `
            --base-pkg $unsignedPath `
            --out-path $outputPath `
            --sign-profile $SignProfile `
            --profiles-path $profiles 2>&1)
        $signExitCode = $LASTEXITCODE
        $signOutput | ForEach-Object { Write-Host $_ }
        if ($signExitCode -eq 0 -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
            break
        }
        $isTransientRepackFailure = ($signOutput -join "`n") -match '(?s)\.tz_repack.*author-signature\.xml.*cannot find the path specified'
        if ($attempt -eq 1 -and $isTransientRepackFailure) {
            Write-Warning 'Tizen signing failed on the first attempt; retrying once to recover from transient .tz_repack failures.'
        } else {
            break
        }
    }
    if ($signExitCode -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Tizen signing failed with exit code $signExitCode."
    }
}

$finalPath = if ($Sign) { $outputPath } else { $unsignedPath }
Write-Host "Packaged Moonlight Flutter widget at $finalPath"
Write-Host "Signed: $Sign"
