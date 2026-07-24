<#
.SYNOPSIS
    IntelliAttend SmartBoard — Production Certification Test Runner

.DESCRIPTION
    Automates validation of the deployment platform (Phases 0–6).
    Scenarios requiring manual verification are marked [MANUAL].

.PARAMETER MsiPath
    Path to the MSI file to test.

.PARAMETER Verbose
    Show detailed output for each test.

.PARAMETER SkipInstall
    Skip installation tests (use if app is already installed).

.PARAMETER OutputDir
    Directory for test evidence. Defaults to .\cert_evidence

.EXAMPLE
    .\cert_test.ps1 -MsiPath ".\build\IASB-5.5.0.msi" -Verbose
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$MsiPath,

    [switch]$Verbose,
    [switch]$SkipInstall,
    [string]$OutputDir = ".\cert_evidence"
)

$ErrorActionPreference = "Continue"
$script:PassCount = 0
$script:FailCount = 0
$script:ManualCount = 0
$script:SkipCount = 0
$script:Results = @()

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-TestResult {
    param([string]$Id, [string]$Name, [string]$Status, [string]$Detail = "")

    $icon = switch ($Status) {
        "PASS"    { "[PASS]" }
        "FAIL"    { "[FAIL]" }
        "MANUAL"  { "[    ]" }
        "SKIP"    { "[SKIP]" }
        default   { "[????]" }
    }

    $color = switch ($Status) {
        "PASS"    { "Green" }
        "FAIL"    { "Red" }
        "MANUAL"  { "Yellow" }
        "SKIP"    { "DarkGray" }
        default   { "White" }
    }

    $line = "$icon $Id - $Name"
    if ($Detail) { $line += " ($Detail)" }
    Write-Host $line -ForegroundColor $color

    $script:Results += [PSCustomObject]@{
        Id = $Id; Name = $Name; Status = $Status; Detail = $Detail
    }

    switch ($Status) {
        "PASS"   { $script:PassCount++ }
        "FAIL"   { $script:FailCount++ }
        "MANUAL" { $script:ManualCount++ }
        "SKIP"   { $script:SkipCount++ }
    }
}

function Test-FileExists {
    param([string]$Path, [string]$Label)
    if (Test-Path $Path) {
        Write-TestResult "" $Label "PASS" $Path
    } else {
        Write-TestResult "" $Label "FAIL" "Not found: $Path"
    }
}

# ── Banner ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IntelliAttend SmartBoard — Production Certification" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "MSI:      $MsiPath"
Write-Host "Evidence: $OutputDir"
Write-Host "Date:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# Create evidence directory
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# ── Pre-flight ───────────────────────────────────────────────────────────────

Write-Host "`n--- PRE-FLIGHT ---" -ForegroundColor Yellow

# Check MSI exists
if (-not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI not found at $MsiPath" -ForegroundColor Red
    exit 1
}
Write-TestResult "PF-01" "MSI file exists" "PASS" $MsiPath

# Check WiX tools available
$candle = Get-Command candle.exe -ErrorAction SilentlyContinue
$light = Get-Command light.exe -ErrorAction SilentlyContinue
if ($candle -and $light) {
    Write-TestResult "PF-02" "WiX tools available" "PASS"
} else {
    Write-TestResult "PF-02" "WiX tools available" "SKIP" "Not needed for runtime tests"
}

# Check deploy_silent.ps1 exists
$deployScript = Join-Path $PSScriptRoot "deploy_silent.ps1"
if (Test-Path $deployScript) {
    Write-TestResult "PF-03" "deploy_silent.ps1 available" "PASS"
} else {
    Write-TestResult "PF-03" "deploy_silent.ps1 available" "FAIL"
}

# ── I. Installation Tests ───────────────────────────────────────────────────

Write-Host "`n--- I. INSTALLATION ---" -ForegroundColor Yellow

$installDir = "$env:LOCALAPPDATA\IntelliAttendSmartBoard"
$configDir = "$installDir\Config"
$dataDir = "$installDir\Data"

if (-not $SkipInstall) {

    # I-01: Clean install
    Write-TestResult "I-01" "Clean install (silent)" "MANUAL" "Run deploy_silent.ps1 -Action Install -MsiPath $MsiPath"

    # I-03: Silent install exit code
    Write-TestResult "I-03" "Silent install exit code" "MANUAL" "Verify msiexec /i ... /qn returns 0 or 3010"

    # Verify directories created
    if (Test-Path $installDir) {
        Write-TestResult "I-01a" "Install directory created" "PASS" $installDir
    } else {
        Write-TestResult "I-01a" "Install directory created" "FAIL" $installDir
    }

    if (Test-Path $configDir) {
        Write-TestResult "I-01b" "Config directory created" "PASS" $configDir
    } else {
        Write-TestResult "I-01b" "Config directory created" "FAIL" $configDir
    }

    if (Test-Path $dataDir) {
        Write-TestResult "I-01c" "Data directory created" "PASS" $dataDir
    } else {
        Write-TestResult "I-01c" "Data directory created" "FAIL" $dataDir
    }

    # Verify env.json written
    $envJson = "$configDir\env.json"
    if (Test-Path $envJson) {
        Write-TestResult "I-01d" "env.json written" "PASS" $envJson
        if ($Verbose) {
            Get-Content $envJson | Write-Host -ForegroundColor DarkGray
        }
    } else {
        Write-TestResult "I-01d" "env.json written" "FAIL" $envJson
    }

    # I-10: App executable exists
    $appExe = "$installDir\App\intelliattend_smartboard.exe"
    Test-FileExists $appExe "I-10 App executable"

} else {
    Write-TestResult "I-XX" "Installation tests" "SKIP" "SkipInstall flag set"
}

# ── II. Uninstallation Tests ────────────────────────────────────────────────

Write-Host "`n--- II. UNINSTALLATION ---" -ForegroundColor Yellow

Write-TestResult "U-01" "Silent uninstall" "MANUAL" "Run deploy_silent.ps1 -Action Uninstall"
Write-TestResult "U-03" "Uninstall preserves Config/" "MANUAL" "Verify Config/ exists after uninstall"
Write-TestResult "U-05" "Uninstall then reinstall" "MANUAL" "Full cycle test"

# ── III. Update / Manifest Tests ────────────────────────────────────────────

Write-Host "`n--- III. UPDATE / MANIFEST POLICY ---" -ForegroundColor Yellow

Write-TestResult "U-07" "Schema version 99 rejected" "MANUAL" "Send manifest with schema_version=99 to board"
Write-TestResult "U-08" "Expired manifest rejected" "MANUAL" "Send manifest with expires_at in past"
Write-TestResult "U-09" "Wrong channel rejected" "MANUAL" "Send beta manifest to stable board"
Write-TestResult "U-10" "Downgrade rejected" "MANUAL" "Send manifest with minimumVersion < installed"
Write-TestResult "U-12" "OS below minimum rejected" "MANUAL" "Send manifest with minimumOsVersion > current"
Write-TestResult "U-14" "HMAC mismatch rejected" "MANUAL" "Send manifest with wrong signature"
Write-TestResult "U-15" "SHA-256 mismatch rejected" "MANUAL" "Tamper MSI after download"
Write-TestResult "U-18" "Force update bypasses rollout" "MANUAL" "Send force=true manifest"

# ── IV. Recovery Tests ──────────────────────────────────────────────────────

Write-Host "`n--- IV. RECOVERY ---" -ForegroundColor Yellow

Write-TestResult "R-01" "Crash loop shows RecoveryScreen" "MANUAL" "Delete critical file, launch 3x"
Write-TestResult "R-04" "Integrity failure — no Launch Anyway" "MANUAL" "Tamper binary, verify button hidden"
Write-TestResult "R-07" "RecoveryScreen retry" "MANUAL" "Click Retry, verify re-runs recovery"
Write-TestResult "R-10" "Recovery after interrupted update" "MANUAL" "Kill process during update, verify recovery"

# ── V. Enterprise Deployment Tests ──────────────────────────────────────────

Write-Host "`n--- V. ENTERPRISE DEPLOYMENT ---" -ForegroundColor Yellow

Write-TestResult "E-01" "Valid deploy_config.json" "MANUAL" "Create config, install, verify app reads it"
Write-TestResult "E-02" "Invalid board_id rejected" "MANUAL" "Use 'INVALID-ID', verify validator rejects"
Write-TestResult "E-07" "env.json fallback" "MANUAL" "Remove deploy_config.json, verify env.json still works"

# ── VI. Stability Tests ─────────────────────────────────────────────────────

Write-Host "`n--- VI. STABILITY ---" -ForegroundColor Yellow

Write-TestResult "S-01" "24-hour continuous run" "MANUAL" "Leave app running, check logs after 24h"
Write-TestResult "S-06" "Power loss during install" "MANUAL" "Kill msiexec mid-install, verify rollback"
Write-TestResult "S-08" "Network loss during heartbeat" "MANUAL" "Disconnect network, verify offline mode"

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PASS:    $script:PassCount" -ForegroundColor Green
Write-Host "  FAIL:    $script:FailCount" -ForegroundColor Red
Write-Host "  MANUAL:  $script:ManualCount" -ForegroundColor Yellow
Write-Host "  SKIP:    $script:SkipCount" -ForegroundColor DarkGray
Write-Host "  TOTAL:   $($script:PassCount + $script:FailCount + $script:ManualCount + $script:SkipCount)"
Write-Host ""

# Save evidence
$evidencePath = "$OutputDir\cert_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$script:Results | Export-Csv -Path $evidencePath -NoTypeInformation
Write-Host "Evidence saved to: $evidencePath" -ForegroundColor Cyan

if ($script:FailCount -gt 0) {
    Write-Host "`nCERTIFICATION: FAILED ($($script:FailCount) failures)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nCERTIFICATION: PASSED (all automated checks pass, $($script:ManualCount) manual scenarios to verify)" -ForegroundColor Green
    exit 0
}
