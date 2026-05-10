param(
    [switch]$Generate,
    [string]$OutputDir = "test/golden"
)

$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Golden Contract Test Runner v1.0               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Run golden contract tests (TOTP, HMAC, token derivation)
Write-Host "▸ Running golden contract tests..." -ForegroundColor Yellow
$testResult = & flutter test test/unit/ 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "  ✓ All golden contracts verified" -ForegroundColor Green
} else {
    Write-Host "  ✗ Golden contract mismatch — check TOTP/HMAC derivation" -ForegroundColor Red
    $testResult | Select-String -Pattern "FAIL|ERROR|expected|Expected" | ForEach-Object {
        Write-Host "    $_" -ForegroundColor Red
    }
    exit 1
}

# Generate golden test data if requested
if ($Generate) {
    Write-Host ""
    Write-Host "▸ Generating golden test vectors..." -ForegroundColor Yellow
    $outputDir = Join-Path $rootDir $OutputDir
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

    $goldenFile = Join-Path $outputDir "golden_vectors.json"
    $goldenData = @{
        "totp" = @{
            "seed" = "MOCK_SEED_123"
            "timestamp_ms" = 1711881234000
            "expected_token" = "IATT::c2Vzc185OTl8MTcxMTg4MTIzNDAwMA==::d4b4648f..."
        }
        "hmac_split" = @{
            "half1" = "mock_half_1_16_bytes"
            "half2" = "mock_half_2_16_bytes"
            "combined" = "mock_half_1_16_bytesmock_half_2_16_bytes"
        }
        "jwt" = @{
            "header" = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            "payload_sample" = "eyJzdWIiOiJJQVNC LTQyMDgiLCJleHAiOjE3MTE4ODEyMzR9"
        }
    } | ConvertTo-Json -Depth 3
    Set-Content -Path $goldenFile -Value $goldenData
    Write-Host "  ✓ Golden vectors saved to $goldenFile" -ForegroundColor Green
}
