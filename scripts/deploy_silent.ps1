#Requires -Version 5.1
<#
.SYNOPSIS
    Enterprise deployment script for IntelliAttend SmartBoard.

.DESCRIPTION
    Installs or uninstalls the IntelliAttend SmartBoard MSI.
    Designed for IT administrators deploying to multiple machines.

    Responsibilities (Installer Contract):
      - Run msiexec silently
      - Write app configuration to Config\env.json
      - Detect GPU compatibility
      - Launch app optionally

    This script does NOT:
      - Contact any network endpoints
      - Perform registration or activation
      - Modify application data

.PARAMETER Action
    Required. 'Install' or 'Uninstall'.

.PARAMETER MsiPath
    Required. Path to the MSI file.

.PARAMETER ApiBaseUrl
    Optional. Override the API base URL.

.PARAMETER FirebaseApiKey
    Optional. Override the Firebase API key.

.PARAMETER FirebaseProjectId
    Optional. Override the Firebase project ID.

.PARAMETER FirebaseAppId
    Optional. Override the Firebase app ID.

.PARAMETER FirebaseMessagingSenderId
    Optional. Override the Firebase messaging sender ID.

.PARAMETER SslPinFingerprint
    Optional. Override the SSL pin fingerprint.

.PARAMETER NoLaunch
    If set, does not launch the app after install.

.PARAMETER PreserveData
    If set (Uninstall only), preserves Data\ and Config\ directories.

.EXAMPLE
    # Silent install
    .\deploy_silent.ps1 -Action Install -MsiPath ".\IASB-5.6.0-x64.msi"

.EXAMPLE
    # Silent install with config
    .\deploy_silent.ps1 -Action Install -MsiPath ".\IASB-5.6.0-x64.msi" `
        -ApiBaseUrl "https://api.intelliattend.app" `
        -FirebaseApiKey "xxx" `
        -FirebaseProjectId "yyy"

.EXAMPLE
    # Silent uninstall
    .\deploy_silent.ps1 -Action Uninstall

.EXAMPLE
    # Uninstall preserving user data
    .\deploy_silent.ps1 -Action Uninstall -PreserveData
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [string]$ApiBaseUrl,
    [string]$FirebaseApiKey,
    [string]$FirebaseProjectId,
    [string]$FirebaseAppId,
    [string]$FirebaseMessagingSenderId,
    [string]$SslPinFingerprint,

    [switch]$NoLaunch,
    [switch]$PreserveData
)

$ErrorActionPreference = "Stop"
$appName = "IntelliAttendSmartBoard"
$rootDir = Join-Path $env:LOCALAPPDATA $appName
$appDir = Join-Path $rootDir "App"
$exePath = Join-Path $appDir "$appName.exe"
$configDir = Join-Path $rootDir "Config"
$logDir = Join-Path $env:TEMP "IntelliAttend\Logs"
$msiexec = Join-Path $env:WINDIR "System32\msiexec.exe"

function Write-Step($message) {
    Write-Host ""
    Write-Host "== $message ==" -ForegroundColor Cyan
}

function Test-ZeroVramVirtualGpu {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($gpu in $gpus) {
        $name = [string]$gpu.Name
        $ram = 0
        if ($null -ne $gpu.AdapterRAM) {
            $ram = [int64]$gpu.AdapterRAM
        }
        if ($ram -eq 0 -and $name -match "Sharing Monitor|Virtual|Remote|Basic") {
            return $true
        }
    }
    return $false
}

# ═══════════════════════════════════════════════════════════════════════════
# INSTALL
# ═══════════════════════════════════════════════════════════════════════════
if ($Action -eq 'Install') {

    if (-not (Test-Path -LiteralPath $MsiPath)) {
        throw "MSI not found: $MsiPath"
    }

    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    Write-Step "System compatibility"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "OS: $($os.Caption) $($os.Version) build $($os.BuildNumber)"

    $useGpuCompatibility = Test-ZeroVramVirtualGpu
    if ($useGpuCompatibility) {
        Write-Warning "Zero-VRAM virtual display adapter detected."
    }

    Write-Step "Writing durable app configuration"
    $hasConfig = -not [string]::IsNullOrWhiteSpace($ApiBaseUrl) -or
        -not [string]::IsNullOrWhiteSpace($FirebaseApiKey) -or
        -not [string]::IsNullOrWhiteSpace($FirebaseProjectId)
    if ($hasConfig) {
        $envJsonFile = Join-Path $configDir "env.json"
        $envLegacyFile = Join-Path $configDir ".env"
        $lines = @()
        if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $lines += "API_BASE_URL=$ApiBaseUrl" }
        if (-not [string]::IsNullOrWhiteSpace($FirebaseApiKey)) { $lines += "FIREBASE_API_KEY=$FirebaseApiKey" }
        if (-not [string]::IsNullOrWhiteSpace($FirebaseProjectId)) { $lines += "FIREBASE_PROJECT_ID=$FirebaseProjectId" }
        if (-not [string]::IsNullOrWhiteSpace($FirebaseAppId)) { $lines += "FIREBASE_APP_ID=$FirebaseAppId" }
        if (-not [string]::IsNullOrWhiteSpace($FirebaseMessagingSenderId)) { $lines += "FIREBASE_MESSAGING_SENDER_ID=$FirebaseMessagingSenderId" }
        if (-not [string]::IsNullOrWhiteSpace($SslPinFingerprint)) { $lines += "SSL_PIN_FINGERPRINT=$SslPinFingerprint" }
        $lines += "ENABLE_DOCUMENTS=true"
        $lines += "DEBUG=false"
        $lines -join "`r`n" | Set-Content -LiteralPath $envJsonFile -Encoding UTF8
        $lines -join "`r`n" | Set-Content -LiteralPath $envLegacyFile -Encoding UTF8
        Write-Host "Config written to: $envJsonFile"
    } else {
        Write-Host "No config overrides provided — app will use built-in defaults."
    }

    Write-Step "Preparing MSI"
    # Copy MSI to temp to avoid SmartScreen/Defender file locks on Downloads folder.
    # When a user downloads an unsigned MSI, SmartScreen and real-time protection may
    # hold a lock on the original file. Running msiexec directly from Downloads can fail
    # with error 1620 ("package could not be opened"). Copying to a fresh temp path
    # creates an unlocked copy that msiexec can always open.
    $msiTempCopy = Join-Path $env:TEMP "IntelliAttend\msi_$(Get-Date -Format yyyyMMdd_HHmmss).msi"
    $msiTempDir = Split-Path $msiTempCopy -Parent
    if (-not (Test-Path $msiTempDir)) { New-Item -ItemType Directory -Path $msiTempDir -Force | Out-Null }
    Copy-Item -LiteralPath $MsiPath -Destination $msiTempCopy -Force
    $msiSizeMB = [math]::Round((Get-Item $msiTempCopy).Length / 1MB, 2)
    Write-Host ("MSI copied to temp: {0} ({1} MB)" -f $msiTempCopy, $msiSizeMB)

    Write-Step "Installing MSI (silent)"
    $installLog = Join-Path $logDir "install_$(Get-Date -Format yyyyMMdd_HHmmss).log"

    # Retry loop: msiexec may fail with error 1620/1619 if SmartScreen Defender
    # is still scanning the file. Retry up to 3 times with 5-second delays.
    $maxRetries = 3
    $retryDelay = 5
    $installExitCode = $null

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Write-Host "Install attempt $attempt of $maxRetries..."
        $installArgs = @("/i", $msiTempCopy, "/qn", "/norestart", "/log", $installLog)
        $process = Start-Process -FilePath $msiexec -ArgumentList $installArgs -Wait -PassThru
        $installExitCode = $process.ExitCode
        Write-Host "MSI exit code: $installExitCode"

        # 0 = success, 3010 = success + reboot required
        if ($installExitCode -eq 0 -or $installExitCode -eq 3010) {
            break
        }

        # 1620 = invalid package, 1619 = package cannot be opened — likely SmartScreen lock
        if ($installExitCode -eq 1620 -or $installExitCode -eq 1619) {
            if ($attempt -lt $maxRetries) {
                Write-Warning "MSI could not be opened (error $installExitCode). SmartScreen/Defender may still be scanning. Retrying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
                # Re-copy in case the temp copy was also flagged
                Copy-Item -LiteralPath $MsiPath -Destination $msiTempCopy -Force
            }
        } else {
            # Different error — no point retrying
            break
        }
    }

    Write-Host "MSI log: $installLog"
    if ($installExitCode -ne 0 -and $installExitCode -ne 3010) {
        throw "MSI install failed with exit code $installExitCode after $maxRetries attempt(s). See $installLog"
    }

    # Clean up temp MSI copy
    Remove-Item -LiteralPath $msiTempCopy -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Install completed but executable not found at $exePath"
    }

    if ($NoLaunch) {
        Write-Host "Install complete. App not launched."
        exit 0
    }

    Write-Step "Launching IntelliAttend"
    $launchArgs = @()
    if ($useGpuCompatibility) {
        $launchArgs += "--intelliattend-high-performance-gpu"
    }
    Start-Process -FilePath $exePath -ArgumentList $launchArgs -WorkingDirectory $appDir
    Write-Host "Started: $exePath"

    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ═══════════════════════════════════════════════════════════════════════════
if ($Action -eq 'Uninstall') {

    Write-Step "Uninstalling IntelliAttend SmartBoard"

    $installLog = Join-Path $logDir "uninstall_$(Get-Date -Format yyyyMMdd_HHmmss).log"
    $uninstallArgs = @("/x", $MsiPath, "/qn", "/norestart", "/log", $installLog)
    $process = Start-Process -FilePath $msiexec -ArgumentList $uninstallArgs -Wait -PassThru
    Write-Host "MSI uninstall exit code: $($process.ExitCode)"
    Write-Host "MSI log: $installLog"
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        throw "MSI uninstall failed with exit code $($process.ExitCode). See $installLog"
    }

    if (-not $PreserveData) {
        Write-Step "Cleaning up application data"
        $dirsToRemove = @($appDir, (Join-Path $rootDir "Cache"), (Join-Path $rootDir "Updates"), (Join-Path $rootDir "Logs"), (Join-Path $rootDir "Backup"))
        foreach ($dir in $dirsToRemove) {
            if (Test-Path -LiteralPath $dir) {
                Remove-Item -LiteralPath $dir -Recurse -Force
                Write-Host "Removed: $dir"
            }
        }
        # Remove root if empty
        if ((Test-Path -LiteralPath $rootDir) -and ((Get-ChildItem -LiteralPath $rootDir -Force | Measure-Object).Count -eq 0)) {
            Remove-Item -LiteralPath $rootDir -Force
            Write-Host "Removed empty root: $rootDir"
        }
    } else {
        Write-Host "Preserving Data\ and Config\ (user data retained)."
    }

    Write-Host "Uninstall complete."
    exit 0
}
