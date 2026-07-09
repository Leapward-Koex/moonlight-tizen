param(
  [string]$Source = "",
  [string]$ProjectRoot = "",
  [switch]$EnableDebugBridge,
  [switch]$DisableDebugBridge,
  [string]$DebugBridgeServerUrl = "",
  [string]$DebugBridgeHostIp = "",
  [int]$DebugBridgePort = 49321,
  [string]$DebugBridgeTokenPath = ""
)

$ErrorActionPreference = "Stop"

function Test-IsInsidePath {
  param(
    [string]$Path,
    [string]$Root
  )

  $rootWithSeparator = if ($Root.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $Root
  } else {
    $Root + [System.IO.Path]::DirectorySeparatorChar
  }

  return $Path.Equals($Root, [System.StringComparison]::OrdinalIgnoreCase) -or
    $Path.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  $ProjectRoot = Join-Path $repoRoot "wasm"
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-IsInsidePath -Path $projectPath -Root $repoRoot)) {
  throw "ProjectRoot must be inside the repository: $projectPath"
}

$requiredRuntimeFiles = @(
  "moonlight-wasm.js",
  "moonlight-wasm.js.mem",
  "moonlight-wasm.wasm",
  "moonlight-wasm.worker.js"
)

$requiredProjectFiles = @(
  "config.xml",
  "icon.png",
  "index.html",
  "platform.js",
  "tizen_web_project.yaml"
)

foreach ($file in $requiredProjectFiles) {
  $path = Join-Path $projectPath $file
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing Tizen extension project file: $path"
  }
}

$candidateSources = @()
if (-not [string]::IsNullOrWhiteSpace($Source)) {
  $candidateSources += $Source
} else {
  $candidateSources += Join-Path $repoRoot "build\widget"
  $candidateSources += Join-Path $repoRoot "build\codex-tizen-run\patched-widget"
}

$sourcePath = $null
foreach ($candidate in $candidateSources) {
  $candidatePath = if ([System.IO.Path]::IsPathRooted($candidate)) {
    $candidate
  } else {
    Join-Path $repoRoot $candidate
  }

  if (-not (Test-Path -LiteralPath $candidatePath -PathType Container)) {
    continue
  }

  $missing = @(
    foreach ($file in $requiredRuntimeFiles) {
      if (-not (Test-Path -LiteralPath (Join-Path $candidatePath $file) -PathType Leaf)) {
        $file
      }
    }
  )

  if ($missing.Count -eq 0) {
    $sourcePath = (Resolve-Path -LiteralPath $candidatePath).Path
    break
  }
}

if ($null -eq $sourcePath) {
  $searched = $candidateSources -join ", "
  throw "Could not find generated Moonlight wasm runtime files. Searched: $searched"
}

if (-not (Test-IsInsidePath -Path $sourcePath -Root $repoRoot)) {
  throw "Source must be inside the repository: $sourcePath"
}

foreach ($file in $requiredRuntimeFiles) {
  Copy-Item -LiteralPath (Join-Path $sourcePath $file) -Destination (Join-Path $projectPath $file) -Force
}

if ($EnableDebugBridge -and $DisableDebugBridge) {
  throw "Use either -EnableDebugBridge or -DisableDebugBridge, not both."
}

if ($EnableDebugBridge -or $DisableDebugBridge) {
  $debugBridgeArgs = @{
    ProjectRoot = $projectPath
  }
  if ($EnableDebugBridge) {
    $debugBridgeArgs.Enable = $true
    if (-not [string]::IsNullOrWhiteSpace($DebugBridgeServerUrl)) {
      $debugBridgeArgs.ServerUrl = $DebugBridgeServerUrl
    }
    if (-not [string]::IsNullOrWhiteSpace($DebugBridgeHostIp)) {
      $debugBridgeArgs.HostIp = $DebugBridgeHostIp
    }
    $debugBridgeArgs.Port = $DebugBridgePort
    if (-not [string]::IsNullOrWhiteSpace($DebugBridgeTokenPath)) {
      $debugBridgeArgs.TokenPath = $DebugBridgeTokenPath
    }
  } else {
    $debugBridgeArgs.Disable = $true
  }

  & (Join-Path $PSScriptRoot "write-debug-bridge-config.ps1") @debugBridgeArgs
}

Write-Host "Synced generated wasm runtime files from $sourcePath to $projectPath"
