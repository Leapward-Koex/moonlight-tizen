[CmdletBinding()]
param(
    [string] $Stage = 'build/flutter-tizen/widget-standard',
    [string] $Output = 'build/flutter-tizen/MoonlightFlutter.wgt',
    [switch] $Sign,
    [string] $SignProfile = 'Scott-Samsung',
    [string] $ProfilesPath = 'build/codex-tizen-run/profiles-scott-samsung-local-pwd.xml',
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
    $profiles = Resolve-WorkspacePath $ProfilesPath -MustExist
    $tz = [IO.Path]::GetFullPath($TzPath)
    if (-not (Test-Path -LiteralPath $tz -PathType Leaf)) {
        throw "Tizen extension CLI not found: $tz"
    }
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    & $tz pack --type wgt `
        --base-pkg $unsignedPath `
        --out-path $outputPath `
        --sign-profile $SignProfile `
        --profiles-path $profiles
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Tizen signing failed with exit code $LASTEXITCODE."
    }
}

$finalPath = if ($Sign) { $outputPath } else { $unsignedPath }
Write-Host "Packaged Moonlight Flutter widget at $finalPath"
Write-Host "Signed: $Sign"
