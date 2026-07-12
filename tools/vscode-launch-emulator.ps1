[CmdletBinding()]
param(
    [switch] $SkipWasm,
    [switch] $SkipFlutter,
    [switch] $ForceGameMode,
    [switch] $EnableDebugBridge,
    [string] $DebugBridgeHostIp = $env:MOONLIGHT_DEBUG_BRIDGE_HOST_IP,
    [string] $Serial = $env:MOONLIGHT_TIZEN_SERIAL,
    [string] $FlutterPath = '',
    [string] $SignProfile = $env:MOONLIGHT_TIZEN_SIGN_PROFILE,
    [string] $ProfilesPath = $env:MOONLIGHT_TIZEN_PROFILES_PATH
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tools = Join-Path $env:USERPROFILE '.tizen-extension-platform\server\sdktools\data\tools'
$sdb = Join-Path $tools 'sdb.exe'
$tz = Join-Path $tools 'tizen-core\tz.exe'

function Get-DotEnvValue([string] $Path, [string] $Name) {
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*$([regex]::Escape($Name))\s*=(.*)$") {
            $value = $Matches[1].Trim()
            if ($value.Length -ge 2 -and
                (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or
                 ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
                return $value.Substring(1, $value.Length - 2)
            }
            return $value
        }
    }
    return $null
}

function New-CurrentUserSigningProfile {
    $envFile = Join-Path $workspace '.env'
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        throw 'Local signing setup requires .env. Alternatively set MOONLIGHT_TIZEN_SIGN_PROFILE and MOONLIGHT_TIZEN_PROFILES_PATH.'
    }

    $certificateName = Get-DotEnvValue $envFile 'CERTNAME2'
    $certificatePassword = Get-DotEnvValue $envFile 'CERTPASSWORD2'
    if ([string]::IsNullOrWhiteSpace($certificateName) -or [string]::IsNullOrWhiteSpace($certificatePassword)) {
        throw 'CERTNAME2 and CERTPASSWORD2 are required in .env for the Samsung signing profile.'
    }

    $certificateRoot = Join-Path $env:USERPROFILE "SamsungCertificate\$certificateName"
    $authorSource = Join-Path $certificateRoot 'author.p12'
    $distributorSource = Join-Path $certificateRoot 'distributor.p12'
    if (-not (Test-Path -LiteralPath $authorSource -PathType Leaf) -or
        -not (Test-Path -LiteralPath $distributorSource -PathType Leaf)) {
        throw "Samsung author/distributor certificates were not found under $certificateRoot."
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $identityKey = [regex]::Replace($identity.User.Value, '[^A-Za-z0-9_.-]', '_')
    $profileRoot = Join-Path $workspace "build\codex-tizen-run\vscode-signing\$identityKey"
    $generatedProfiles = Join-Path $profileRoot 'profiles.xml'
    $generatedProfileName = 'Moonlight-VSCode'

    if (-not (Test-Path -LiteralPath $generatedProfiles -PathType Leaf)) {
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        $authorCopy = Join-Path $profileRoot 'author.p12'
        $distributorCopy = Join-Path $profileRoot 'distributor.p12'
        Copy-Item -LiteralPath $authorSource -Destination $authorCopy -Force
        Copy-Item -LiteralPath $distributorSource -Destination $distributorCopy -Force

        # tz writes user-bound encrypted .pwd files beside these ignored
        # certificate copies. Suppress its output so the password is never logged.
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $tz security-profiles add -n $generatedProfileName -x $generatedProfiles `
                -a $authorCopy -p $certificatePassword `
                -d $distributorCopy -P $certificatePassword *> $null
            $profileExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorAction
            $certificatePassword = $null
        }
        if ($profileExitCode -ne 0 -or -not (Test-Path -LiteralPath $generatedProfiles -PathType Leaf)) {
            throw "Tizen could not create the current-user signing profile (exit code $profileExitCode)."
        }
        Write-Host "Created a Tizen signing profile for $($identity.Name)."
    }

    return [pscustomobject]@{
        Name = $generatedProfileName
        Path = $generatedProfiles
    }
}

if (-not (Test-Path -LiteralPath $sdb -PathType Leaf)) {
    throw "Tizen VS Code extension tools were not found at $tools. Install the extension and start a TV emulator."
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $deviceOutput = @(& $sdb devices 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list Tizen devices:`n$($deviceOutput -join [Environment]::NewLine)"
    }
    $devices = @(
        $deviceOutput | ForEach-Object {
            if ($_ -match '^\s*(\S+)\s+device(?:\s|$)') { $Matches[1] }
        }
    )
    if ($devices.Count -eq 0) {
        throw 'No attached Tizen emulator was found. Start the TV emulator, then try F5 again.'
    }
    if ($devices.Count -gt 1) {
        throw "More than one Tizen device is attached ($($devices -join ', ')). Set MOONLIGHT_TIZEN_SERIAL to choose one."
    }
    $Serial = $devices[0]
}

if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutter) {
        $FlutterPath = $flutter.Source
    } else {
        $fvmFlutter = Join-Path $env:USERPROFILE 'fvm\default\bin\flutter.bat'
        if (Test-Path -LiteralPath $fvmFlutter -PathType Leaf) {
            $FlutterPath = $fvmFlutter
        }
    }
}

# Password files generated by Tizen are bound to the Windows identity that
# created them. Generate an ignored per-user profile instead of sharing one.
if ([string]::IsNullOrWhiteSpace($SignProfile) -and [string]::IsNullOrWhiteSpace($ProfilesPath)) {
    $generatedProfile = New-CurrentUserSigningProfile
    $SignProfile = $generatedProfile.Name
    $ProfilesPath = $generatedProfile.Path
} elseif ([string]::IsNullOrWhiteSpace($SignProfile) -or [string]::IsNullOrWhiteSpace($ProfilesPath)) {
    throw 'Both signing profile and profiles path are required. Set both MOONLIGHT_TIZEN_SIGN_PROFILE and MOONLIGHT_TIZEN_PROFILES_PATH.'
}

$profilesFullPath = if ([IO.Path]::IsPathRooted($ProfilesPath)) {
    [IO.Path]::GetFullPath($ProfilesPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $ProfilesPath))
}
if (-not (Test-Path -LiteralPath $profilesFullPath -PathType Leaf)) {
    throw "Signing profiles file not found: $profilesFullPath. Set MOONLIGHT_TIZEN_SIGN_PROFILE and MOONLIGHT_TIZEN_PROFILES_PATH, then try again."
}
Write-Host "Signing profile: $SignProfile"
Write-Host "Profiles file: $profilesFullPath"

$arguments = @{
    Serial = $Serial
    FlutterPath = $FlutterPath
    SignProfile = $SignProfile
    ProfilesPath = $profilesFullPath
    SkipWasm = $SkipWasm
    SkipFlutter = $SkipFlutter
    ForceGameMode = $ForceGameMode
    EnableDebugBridge = $EnableDebugBridge
}
if (-not [string]::IsNullOrWhiteSpace($DebugBridgeHostIp)) {
    $arguments.DebugBridgeHostIp = $DebugBridgeHostIp
}

Write-Host "Building and deploying Moonlight Flutter to $Serial..."
& (Join-Path $workspace 'packaging\flutter_tizen\build-emulator.ps1') @arguments
