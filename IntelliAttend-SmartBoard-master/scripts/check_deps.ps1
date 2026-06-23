param(
    [switch]$Fix,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

$vulnCount = 0
$outdatedCount = 0

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Dependency Security Scanner v1.0               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── 1. Dart / Flutter dependencies ─────────────────────────
Write-Host "▸ [1/3] Scanning Flutter/Dart dependencies..." -ForegroundColor Yellow
$auditResult = & dart pub audit 2>&1
$auditExit = $LASTEXITCODE

if ($auditExit -ne 0) {
    $vulnLines = $auditResult | Where-Object { $_ -match "vulnerabilit" -or $_ -match "CVE" -or $_ -match "CWE" }
    $vulnCount = ($vulnLines | Measure-Object).Count
    Write-Host "  ✗ $vulnCount vulnerabilities detected" -ForegroundColor Red
    if ($Verbose) {
        $auditResult | ForEach-Object { Write-Host "  $_" }
    }
} else {
    Write-Host "  ✓ No vulnerabilities found" -ForegroundColor Green
}

Write-Host ""

# ── 2. Python backend dependencies ─────────────────────────
Write-Host "▸ [2/3] Scanning Python dependencies..." -ForegroundColor Yellow
$reqFile = "$rootDir\backend\python\requirements.txt"
if (Test-Path $reqFile) {
    $pipAudit = & pip list --format=columns --outdated 2>&1
    $outdatedLines = $pipAudit | Where-Object { $_ -match "^\w" -and $_ -notmatch "Package.*Version" -and $_ -notmatch "^-+" }
    $outdatedCount = ($outdatedLines | Measure-Object).Count

    # Check for pip-audit
    $hasPipAudit = $null -ne (Get-Command "pip-audit" -ErrorAction SilentlyContinue)
    if ($hasPipAudit) {
        $pipVuln = & pip-audit 2>&1
        $pipVulnLines = $pipVuln | Where-Object { $_ -match "CVE|CWE|vulnerable" }
        $vulnCount += ($pipVulnLines | Measure-Object).Count
        if ($pipVulnLines) {
            Write-Host "  ✗ Python vulns found:" -ForegroundColor Red
            $pipVulnLines | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Host "  ✓ No Python vulnerabilities" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠ pip-audit not installed — run: pip install pip-audit" -ForegroundColor Yellow
        Write-Host "    (Skipping Python vulnerability scan)" -ForegroundColor Gray
    }

    if ($outdatedCount -gt 0) {
        Write-Host "  ⚠ $outdatedCount outdated packages" -ForegroundColor Yellow
        if ($Verbose) {
            $outdatedLines | ForEach-Object { Write-Host "    $_" }
        }
    } else {
        Write-Host "  ✓ All Python packages up-to-date" -ForegroundColor Green
    }

    if ($Fix -and $outdatedCount -gt 0) {
        Write-Host "  ▸ Upgrading packages..." -ForegroundColor Cyan
        & pip install -r $reqFile --upgrade 2>&1 | Out-Null
        & pip list --outdated --format=columns | ForEach-Object { Write-Host "    $_" }
    }
} else {
    Write-Host "  ⚠ No requirements.txt found at $reqFile" -ForegroundColor Yellow
}

Write-Host ""

# ── 3. Summary ─────────────────────────────────────────────
Write-Host "▸ [3/3] Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  DEPENDENCY SCAN RESULTS                         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

if ($vulnCount -eq 0 -and $outdatedCount -eq 0) {
    Write-Host "║  ✓ All dependencies clean                        ║" -ForegroundColor Green
    $exitCode = 0
} elseif ($vulnCount -gt 0) {
    Write-Host "║  ✗ $vulnCount known vulnerabilities                ║" -ForegroundColor Red
    $exitCode = 1
} else {
    Write-Host "║  ⚠ $outdatedCount outdated packages                 ║" -ForegroundColor Yellow
    $exitCode = 0
}
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

exit $exitCode
