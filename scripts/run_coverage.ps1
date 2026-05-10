param(
    [switch]$Quiet,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

if (-not $Quiet) {
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Coverage Report Generator v1.0                 ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

# ── Step 1: Run tests with coverage ────────────────────────
if (-not $Quiet) {
    Write-Host "▸ Running tests with coverage..." -ForegroundColor Yellow
}
$testResult = & flutter test --coverage 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Tests failed — cannot generate coverage" -ForegroundColor Red
    exit 1
}

$coverageFile = "coverage/lcov.info"
if (-not (Test-Path $coverageFile)) {
    Write-Host "  ✗ Coverage data not found at $coverageFile" -ForegroundColor Red
    exit 1
}

# ── Step 2: Parse coverage info ────────────────────────────
$lcovContent = Get-Content $coverageFile -Raw
$totalLines = 0
$hitLines = 0
$fileData = @{}

# Simple lcov parser
$currentFile = ""
Get-Content $coverageFile | ForEach-Object {
    if ($_ -match "^SF:(.+)") {
        $currentFile = $matches[1]
        if (-not $fileData.ContainsKey($currentFile)) {
            $fileData[$currentFile] = @{total = 0; hit = 0}
        }
    } elseif ($_ -match "^DA:(\d+),(\d+)") {
        $fileData[$currentFile].total++
        if ($matches[2] -ne "0") {
            $fileData[$currentFile].hit++
            $hitLines++
        }
        $totalLines++
    }
}

$overallPct = if ($totalLines -gt 0) { [math]::Round($hitLines / $totalLines * 100, 1) } else { 0 }

# ── Step 3: Display report ────────────────────────────────
if (-not $Quiet) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  COVERAGE REPORT                                ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Overall: $($overallPct.ToString().PadLeft(5))%  ($hitLines/$totalLines lines)         ║" -ForegroundColor $(if ($overallPct -ge 80) {"Green"} elseif ($overallPct -ge 50) {"Yellow"} else {"Red"})
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Target: 80%                                     ║" -ForegroundColor Gray
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Per-file breakdown
    Write-Host "  Per-file breakdown:" -ForegroundColor Yellow
    $fileData.GetEnumerator() | Sort-Object { $_.Value.hit / [math]::Max($_.Value.total, 1) } | ForEach-Object {
        $pct = if ($_.Value.total -gt 0) { [math]::Round($_.Value.hit / $_.Value.total * 100, 1) } else { 0 }
        $color = if ($pct -ge 80) { "Green" } elseif ($pct -ge 50) { "Yellow" } else { "Red" }
        $shortPath = $_.Key -replace [regex]::Escape("$rootDir\"), ""
        Write-Host "  $($pct.ToString().PadLeft(6))%  $shortPath" -ForegroundColor $color
    }
}

# ── Step 4: Generate HTML report ───────────────────────────
$htmlReport = "coverage/html"
$hasLcov = $null -ne (Get-Command "genhtml" -ErrorAction SilentlyContinue)

if ($hasLcov) {
    & genhtml -o $htmlReport $coverageFile --quiet 2>&1 | Out-Null
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "▸ HTML report: $htmlReport\index.html" -ForegroundColor Green
        if ($Open) {
            Start-Process "$htmlReport\index.html"
        }
    }
} elseif (-not $Quiet) {
    Write-Host ""
    Write-Host "  ── Note ──" -ForegroundColor Yellow
    Write-Host "  Install lcov (choco install lcov) for HTML reports" -ForegroundColor Yellow
    Write-Host "  Raw data: $coverageFile" -ForegroundColor Yellow
}

return $overallPct
