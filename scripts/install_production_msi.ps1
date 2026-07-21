param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$FirebaseApiKey,

    [Parameter(Mandatory = $true)]
    [string]$FirebaseProjectId,

    [Parameter(Mandatory = $true)]
    [string]$FirebaseAppId,

    [Parameter(Mandatory = $true)]
    [string]$FirebaseMessagingSenderId,

    [Parameter(Mandatory = $true)]
    [string]$SslPinFingerprint,

    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$appName = "intelliattend_smartboard"
$configDir = Join-Path $env:LOCALAPPDATA "IntelliAttendSmartBoard"
$installDir = Join-Path $env:LOCALAPPDATA $appName
$exePath = Join-Path $installDir "$appName.exe"
$logDir = Join-Path $env:TEMP "IntelliAttendInstall"
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

if (-not (Test-Path -LiteralPath $MsiPath)) {
    throw "MSI not found: $MsiPath"
}

if ([string]::IsNullOrWhiteSpace($SslPinFingerprint)) {
    throw "SSL pin fingerprint is required for production installs."
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Write-Step "System compatibility"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption) $($os.Version) build $($os.BuildNumber)"
Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Select-Object Name, DriverVersion, AdapterRAM |
    Format-Table -AutoSize

$useGpuCompatibility = Test-ZeroVramVirtualGpu
if ($useGpuCompatibility) {
    Write-Warning "Zero-VRAM virtual display adapter detected. The app will launch in GPU compatibility mode."
}

Write-Step "Writing durable app configuration"
$envFile = Join-Path $configDir ".env"
@"
API_BASE_URL=$ApiBaseUrl
FIREBASE_API_KEY=$FirebaseApiKey
FIREBASE_PROJECT_ID=$FirebaseProjectId
FIREBASE_APP_ID=$FirebaseAppId
FIREBASE_MESSAGING_SENDER_ID=$FirebaseMessagingSenderId
SSL_PIN_FINGERPRINT=$SslPinFingerprint
ENABLE_DOCUMENTS=true
DEBUG=false
"@ | Set-Content -LiteralPath $envFile -Encoding UTF8
Write-Host "Config: $envFile"

Write-Step "Installing MSI"
$installLog = Join-Path $logDir "install_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$installArgs = @("/i", (Resolve-Path -LiteralPath $MsiPath).Path, "/passive", "/norestart", "/log", $installLog)
$process = Start-Process -FilePath $msiexec -ArgumentList $installArgs -Wait -PassThru
Write-Host "MSI exit code: $($process.ExitCode)"
Write-Host "MSI log: $installLog"
if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
    throw "MSI install failed with exit code $($process.ExitCode). See $installLog"
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Install completed but executable was not found at $exePath"
}

if ($NoLaunch) {
    Write-Host "Install complete. Launch skipped."
    exit 0
}

Write-Step "Launching IntelliAttend"
$launchArgs = @()
if ($useGpuCompatibility) {
    $launchArgs += "--intelliattend-high-performance-gpu"
}
Start-Process -FilePath $exePath -ArgumentList $launchArgs -WorkingDirectory $installDir
Write-Host "Started: $exePath $($launchArgs -join ' ')"
