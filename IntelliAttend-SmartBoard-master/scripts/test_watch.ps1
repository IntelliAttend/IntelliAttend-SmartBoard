param(
    [string]$TestPath = "",
    [switch]$Coverage
)

$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  TDD Watch Mode — Ctrl+C to stop                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$watchArgs = @("test")
if ($TestPath) { $watchArgs += $TestPath }

# Watch via repeated execution (flutter has no native --watch yet)
while ($true) {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Watching for changes — $(Get-Date -Format 'HH:mm:ss')                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $testResult = & flutter $watchArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "  ✓ All tests passed" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Tests failed" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Waiting for file changes... (Ctrl+C to exit)" -ForegroundColor Gray
    Start-Sleep -Seconds 2
}
