<#
.SYNOPSIS
    Build and sign the IntelliAttend SmartBoard MSI.

.DESCRIPTION
    PowerShell alternative to build_msi.bat with integrated signing support.
    Builds the MSI from the Flutter release output and optionally signs all binaries.

.PARAMETER Version
    Version string (e.g., "5.5.0"). Required.

.PARAMETER SourceDir
    Flutter build output directory. Default: build\windows\x64\runner\Release

.PARAMETER SkipSigning
    Skip the code signing step.

.PARAMETER PfxPath
    Path to the signing certificate .pfx file. Default: scripts\certs\intelliattend_signing.pfx

.PARAMETER PfxPassword
    Password for the .pfx file. If not provided and signing is enabled, reads from
    WIX_SIGN_PASSWORD environment variable or prompts.

.PARAMETER OutputDir
    Directory for the final MSI. Default: build\msi

.EXAMPLE
    .\build_msi.ps1 -Version "5.6.0"

.EXAMPLE
    .\build_msi.ps1 -Version "5.6.0" -SkipSigning

.EXAMPLE
    .\build_msi.ps1 -Version "5.6.0" -PfxPath "C:\certs\signing.pfx" -PfxPassword (Read-Host -AsSecureString)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$SourceDir = "build\windows\x64\runner\Release",
    [string]$OutputDir = "build\msi",
    [switch]$SkipSigning,
    [string]$PfxPath = "scripts\certs\intelliattend_signing.pfx",
    [SecureString]$PfxPassword,
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IntelliAttend SmartBoard MSI Builder" -ForegroundColor Cyan
Write-Host " Version: $Version" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ── Validate prerequisites ───────────────────────────────────────────────────

Write-Host "--- Pre-flight Checks ---" -ForegroundColor Yellow

# Check WiX tools
$candle = Get-Command candle.exe -ErrorAction SilentlyContinue
$light = Get-Command light.exe -ErrorAction SilentlyContinue
if (-not $candle -or -not $light) {
    Write-Host "ERROR: WiX Toolset not found. Install via: choco install wixtoolset" -ForegroundColor Red
    exit 1
}
Write-Host "  WiX Toolset: OK" -ForegroundColor Green

# Check source directory
$sourcePath = Join-Path $projectRoot $SourceDir
if (-not (Test-Path $sourcePath)) {
    Write-Host "ERROR: Source directory not found: $sourcePath" -ForegroundColor Red
    Write-Host "  Run 'flutter build windows --release' first." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Source dir: OK ($sourcePath)" -ForegroundColor Green

# Check key files
$exePath = Join-Path $sourcePath "intelliattend_smartboard.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: intelliattend_smartboard.exe not found in $sourcePath" -ForegroundColor Red
    exit 1
}
Write-Host "  EXE found: OK" -ForegroundColor Green

$updateAgentPath = Join-Path $sourcePath "update_agent.exe"
if (-not (Test-Path $updateAgentPath)) {
    Write-Host "WARNING: update_agent.exe not found" -ForegroundColor Yellow
}

# ── Step 1: Compile WiX ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "--- [1/3] Compiling WiX Source ---" -ForegroundColor Yellow

# Ensure output directory
$msiOutDir = Join-Path $projectRoot $OutputDir
if (-not (Test-Path $msiOutDir)) { New-Item -ItemType Directory -Path $msiOutDir -Force | Out-Null }

$wxsSource = Join-Path $projectRoot "windows\installer\product.wxs"
$wixObj = Join-Path $msiOutDir "product.wixobj"

Push-Location (Join-Path $projectRoot "windows\installer")
try {
    & candle.exe `
        -dAppName="IntelliAttendSmartBoard" `
        -dVersion="$Version" `
        -dSourceDir="$sourcePath" `
        -arch x64 `
        -ext WixUIExtension `
        -out $wixObj `
        product.wxs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: WiX compilation failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "  WiX compiled successfully" -ForegroundColor Green
} finally {
    Pop-Location
}

# ── Step 2: Link MSI ────────────────────────────────────────────────────────

Write-Host ""
Write-Host "--- [2/3] Linking MSI ---" -ForegroundColor Yellow

$msiName = "IntelliAttendSmartBoard-$Version-x64.msi"
$msiPath = Join-Path $msiOutDir $msiName

& light.exe `
    -ext WixUIExtension `
    -spdb `
    -sice:ICE61 `
    -out $msiPath `
    $wixObj

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: WiX linking failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

$msiSize = [math]::Round((Get-Item $msiPath).Length / 1MB, 2)
Write-Host "  MSI created: $msiPath ($msiSize MB)" -ForegroundColor Green

# ── Step 3: Sign ─────────────────────────────────────────────────────────────

if (-not $SkipSigning) {
    Write-Host ""
    Write-Host "--- [3/4] Signing Binaries ---" -ForegroundColor Yellow

    $signScript = Join-Path $PSScriptRoot "sign_binaries.ps1"
    $signArgs = @{
        SourceDir      = $sourcePath
        MsiPath        = $msiPath
        TimestampServer = $TimestampServer
    }

    # Determine certificate source
    $resolvedPfx = $PfxPath
    if (-not [System.IO.Path]::IsPathRooted($resolvedPfx)) {
        $resolvedPfx = Join-Path $projectRoot $PfxPath
    }

    if (Test-Path $resolvedPfx) {
        $signArgs.PfxPath = $resolvedPfx
        if ($PfxPassword) {
            $signArgs.Password = $PfxPassword
        } elseif ($env:WIX_SIGN_PASSWORD) {
            $signArgs.Password = ConvertTo-SecureString $env:WIX_SIGN_PASSWORD -AsPlainText -Force
        } else {
            Write-Host "No password provided. Enter PFX password:" -ForegroundColor Yellow
            $signArgs.Password = Read-Host -Prompt "PFX Password" -AsSecureString
        }
    } elseif ($env:WIX_SIGN_CERT_BASE64 -and $env:WIX_SIGN_PASSWORD) {
        # CI/CD mode - env vars loaded by sign_binaries.ps1
        Write-Host "Using CI/CD certificate from environment variables" -ForegroundColor Yellow
    } else {
        Write-Host "WARN: No signing certificate found. Skipping signing." -ForegroundColor Yellow
        Write-Host "  Run scripts\create_signing_cert.ps1 to generate one." -ForegroundColor Yellow
        $SkipSigning = $true
    }

    if (-not $SkipSigning) {
        & $signScript @signArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARN: Signing failed. MSI will be unsigned." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host ""
    Write-Host "--- [3/4] Signing Skipped ---" -ForegroundColor DarkGray
}

# ── Step 4: Build Bootstrapper ───────────────────────────────────────────────

Write-Host ""
Write-Host "--- [4/4] Building Bootstrapper ---" -ForegroundColor Yellow

$bootstrapperDir = Join-Path $projectRoot "windows\bootstrapper"
$bootstrapperBuildDir = Join-Path $projectRoot "build\bootstrapper"

if (-not (Test-Path $bootstrapperBuildDir)) { New-Item -ItemType Directory -Path $bootstrapperBuildDir -Force | Out-Null }

Push-Location $bootstrapperBuildDir
try {
    & cmake.exe "$bootstrapperDir" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Bootstrapper CMake configure failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    & cmake.exe --build . --config Release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Bootstrapper build failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $bootstrapperExe = Join-Path $bootstrapperBuildDir "bootstrapper.exe"
    if (-not (Test-Path $bootstrapperExe)) {
        Write-Host "ERROR: bootstrapper.exe not found in build output" -ForegroundColor Red
        exit 1
    }

    # Copy bootstrapper to MSI output directory with proper name.
    $bootstrapperDest = Join-Path $msiOutDir "IntelliAttendSmartBoard-$Version-x64-Setup.exe"
    Copy-Item -Path $bootstrapperExe -Destination $bootstrapperDest -Force
    Write-Host "  Bootstrapper: $bootstrapperDest" -ForegroundColor Green

    # Sign bootstrapper if signing is enabled.
    if (-not $SkipSigning) {
        $cert = $null
        $resolvedPfxCheck = $PfxPath
        if (-not [System.IO.Path]::IsPathRooted($resolvedPfxCheck)) {
            $resolvedPfxCheck = Join-Path $projectRoot $PfxPath
        }

        if (Test-Path $resolvedPfxCheck) {
            $pwd = if ($PfxPassword) { $PfxPassword } elseif ($env:WIX_SIGN_PASSWORD) { ConvertTo-SecureString $env:WIX_SIGN_PASSWORD -AsPlainText -Force } else { $null }
            if ($pwd) { $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($resolvedPfxCheck, $pwd) }
        } elseif ($env:WIX_SIGN_CERT_BASE64 -and $env:WIX_SIGN_PASSWORD) {
            $certBytes = [Convert]::FromBase64String($env:WIX_SIGN_CERT_BASE64)
            $certPwd = ConvertTo-SecureString $env:WIX_SIGN_PASSWORD -AsPlainText -Force
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certBytes, $certPwd)
        }

        if ($cert) {
            $sig = Set-AuthenticodeSignature -FilePath $bootstrapperDest -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256
            if ($sig.Status -eq "Valid") {
                Write-Host "  Bootstrapper signed successfully" -ForegroundColor Green
            } else {
                Write-Host "  WARN: Bootstrapper signing failed: $($sig.Status) - $($sig.StatusMessage)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  WARN: No certificate available for bootstrapper signing" -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}

# ── Compute SHA-256 ──────────────────────────────────────────────────────────

Write-Host ""
Write-Host "--- Post-build ---" -ForegroundColor Yellow

$hash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash.ToLower()
$hashFile = Join-Path $msiOutDir "IntelliAttendSmartBoard-$Version.sha256"
$hash | Out-File -FilePath $hashFile -NoNewline
Write-Host "  SHA-256: $hash"
Write-Host "  Hash file: $hashFile"

$bootstrapperHash = ""
$bootstrapperDest = Join-Path $msiOutDir "IntelliAttendSmartBoard-$Version-x64-Setup.exe"
if (Test-Path $bootstrapperDest) {
    $bootstrapperHash = (Get-FileHash -Path $bootstrapperDest -Algorithm SHA256).Hash.ToLower()
    Write-Host "  Bootstrapper SHA-256: $bootstrapperHash"
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " BUILD COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  MSI:          $msiPath ($msiSize MB)"
Write-Host "  Bootstrapper: $bootstrapperDest"
Write-Host "  SHA256:       $hash"

# Verify signing
if (-not $SkipSigning) {
    $sig = Get-AuthenticodeSignature $msiPath
    Write-Host "  MSI Signed:   $($sig.Status)" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
    if (Test-Path $bootstrapperDest) {
        $sigBs = Get-AuthenticodeSignature $bootstrapperDest
        Write-Host "  EXE Signed:   $($sigBs.Status)" -ForegroundColor $(if ($sigBs.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
    }
}

Write-Host ""
