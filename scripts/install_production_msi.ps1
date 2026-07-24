param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [string]$ApiBaseUrl,
    [string]$FirebaseApiKey,
    [string]$FirebaseProjectId,
    [string]$FirebaseAppId,
    [string]$FirebaseMessagingSenderId,
    [string]$SslPinFingerprint,

    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$appName = "IntelliAttendSmartBoard"
$rootDir = Join-Path $env:LOCALAPPDATA $appName
$configDir = Join-Path $rootDir "Config"
$appDir = Join-Path $rootDir "App"
$exePath = Join-Path $appDir "$appName.exe"
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

if (-not (Test-Path -LiteralPath $MsiPath)) {
    throw "MSI not found: $MsiPath"
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
$hasConfig = -not [string]::IsNullOrWhiteSpace($ApiBaseUrl) -or
    -not [string]::IsNullOrWhiteSpace($FirebaseApiKey) -or
    -not [string]::IsNullOrWhiteSpace($FirebaseProjectId)
if ($hasConfig) {
    # Write config as env.json (new convention) and .env (legacy fallback).
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
    Write-Host "Config: $envJsonFile"
} else {
    Write-Host "No config overrides provided - app will use built-in production defaults."
}

Write-Step "Installing MSI"
$tempMsi = Join-Path $env:TEMP "intelliattend_install.msi"
Copy-Item -LiteralPath $MsiPath -Destination $tempMsi -Force
Write-Host "Copied MSI to temp: $tempMsi"
$installLog = Join-Path $logDir "install_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$installArgs = @("/i", $tempMsi, "/passive", "/norestart", "/log", $installLog)
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
Start-Process -FilePath $exePath -ArgumentList $launchArgs -WorkingDirectory $appDir
Write-Host "Started: $exePath $($launchArgs -join ' ')"
