param(
    [switch]$Coverage,
    [switch]$Verbose,
    [string]$TestPath = ""
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

$passed = 0
$failed = 0
$skipped = 0

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  IntelliAttend SmartBoard — Test Runner v1.0    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Dart Analysis ──────────────────────────────────
Write-Host "▸ STEP 1/3: Static Analysis (flutter analyze)..." -ForegroundColor Yellow
$analyzeResult = & flutter analyze 2>&1
$analyzeExit = $LASTEXITCODE

if ($analyzeExit -ne 0) {
    $errorLines = $analyzeResult | Where-Object { $_ -match "error|warning|issue" }
    Write-Host "  ✗ Analysis FAILED — $($errorLines.Count) issues found" -ForegroundColor Red
    Write-Host ""
    $analyzeResult | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "  ── Fix hints ──" -ForegroundColor Yellow
    Write-Host "  Run: .\scripts\fix_analyze.ps1  to auto-fix" -ForegroundColor Yellow
    Write-Host ""
    $failed++
} else {
    Write-Host "  ✓ Analysis passed (0 errors, 0 warnings)" -ForegroundColor Green
    $passed++
}

# ── Step 2: Run Flutter Tests ──────────────────────────────
Write-Host ""
Write-Host "▸ STEP 2/3: Running tests (flutter test)..." -ForegroundColor Yellow

$testArgs = @("test", "--reporter", "expanded")
if ($Coverage) { $testArgs += "--coverage" }
if ($TestPath) { $testArgs += $TestPath }

$testResult = & flutter $testArgs 2>&1
$testExit = $LASTEXITCODE

Write-Host ""
if ($testExit -ne 0) {
    Write-Host "  ✗ Some tests FAILED" -ForegroundColor Red
    $failed++
} else {
    Write-Host "  ✓ All tests passed" -ForegroundColor Green
    $passed++
}

# Extract test summary from output
$summaryLine = $testResult | Select-String -Pattern "All tests passed|Some tests failed|\d+ tests? passed|\d+ tests? failed"
if ($summaryLine) {
    Write-Host "  ── $($summaryLine.Line)" -ForegroundColor Gray
}

# ── Step 3: Coverage Report (if enabled) ──────────────────
if ($Coverage) {
    Write-Host ""
    Write-Host "▸ STEP 3/3: Generating coverage report..." -ForegroundColor Yellow
    & "$PSScriptRoot\run_coverage.ps1" -Quiet
}

# ── Summary ────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RESULTS                                        ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
if ($passed -gt 0 -and $failed -eq 0) {
    Write-Host "║  ✓ ALL CHECKS PASSED                            ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "║  ✗ $failed step(s) FAILED                          ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    exit 1
}
