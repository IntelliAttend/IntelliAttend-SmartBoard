$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Auto-Fix: Analysis Issues                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Format all Dart files ──────────────────────────
Write-Host "▸ Formatting Dart files (dart format)..." -ForegroundColor Yellow
$formatResult = & dart format lib/ test/ 2>&1
Write-Host "  $formatResult" -ForegroundColor Gray

# ── Step 2: Run full analysis ──────────────────────────────
Write-Host ""
Write-Host "▸ Re-running analysis..." -ForegroundColor Yellow
$analyzeResult = & flutter analyze 2>&1
$analyzeExit = $LASTEXITCODE

if ($analyzeExit -eq 0) {
    Write-Host "  ✓ Analysis clean" -ForegroundColor Green
    exit 0
} else {
    $errorCount = ($analyzeResult | Select-String -Pattern "error" | Measure-Object).Count
    $warnCount = ($analyzeResult | Select-String -Pattern "warning" | Measure-Object).Count
    Write-Host "  ⚠ $errorCount errors, $warnCount warnings remaining" -ForegroundColor Yellow
    Write-Host "  (Manual fixes required for remaining issues)" -ForegroundColor Gray
    $analyzeResult | ForEach-Object { Write-Host "  $_" }
    exit 1
}
