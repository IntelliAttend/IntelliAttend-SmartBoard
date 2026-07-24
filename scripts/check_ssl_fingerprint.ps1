<#
.SYNOPSIS
    Check if the production SSL certificate fingerprint matches the configured pin.

.DESCRIPTION
    Connects to the production API server, extracts the current TLS certificate
    fingerprint, and compares it against the SSL_PIN_FINGERPRINT configured in
    the .env file or the repository secret.

    Use cases:
      - CI pre-build gate: fail the build if fingerprint is stale
      - Scheduled monitoring: alert if cert has renewed
      - Manual check: extract current fingerprint for updating .env

.PARAMETER ApiHost
    The API host to check. Default: api.intelliattend.app

.PARAMETER ExpectedFingerprint
    The fingerprint to compare against. If not provided, reads from .env file.

.PARAMETER OutputJson
    Output results as JSON (for CI consumption).

.PARAMETER UpdateEnv
    If set, updates the .env file with the new fingerprint when mismatch is detected.

.EXAMPLE
    .\check_ssl_fingerprint.ps1

.EXAMPLE
    .\check_ssl_fingerprint.ps1 -OutputJson

.EXAMPLE
    .\check_ssl_fingerprint.ps1 -ExpectedFingerprint "51f46a5d..."
#>

param(
    [string]$ApiHost = "api.intelliattend.app",
    [string]$ExpectedFingerprint,
    [switch]$OutputJson,
    [switch]$UpdateEnv
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$result = @{
    api_host          = $ApiHost
    expected          = $null
    actual_sha256     = $null
    actual_sha1       = $null
    match             = $false
    cert_subject      = $null
    cert_expires      = $null
    days_until_expiry = $null
    status            = "unknown"
    error             = $null
}

# ── Resolve expected fingerprint ──────────────────────────────────────────────

if ($ExpectedFingerprint) {
    $result.expected = $ExpectedFingerprint
    Write-Host "Using provided fingerprint: $($ExpectedFingerprint.Substring(0, [Math]::Min(16, $ExpectedFingerprint.Length)))..." -ForegroundColor Yellow
} else {
    # Try .env file
    $envPath = Join-Path $projectRoot ".env"
    if (Test-Path $envPath) {
        $envContent = Get-Content $envPath -Raw
        if ($envContent -match 'SSL_PIN_FINGERPRINT=(\S+)') {
            $result.expected = $Matches[1]
            Write-Host "Read from .env: $($result.expected.Substring(0, [Math]::Min(16, $result.expected.Length)))..." -ForegroundColor Yellow
        }
    }

    # Try environment variable (CI/CD)
    if (-not $result.expected -and $env:SSL_PIN_FINGERPRINT) {
        $result.expected = $env:SSL_PIN_FINGERPRINT
        Write-Host "Read from env var: $($result.expected.Substring(0, [Math]::Min(16, $result.expected.Length)))..." -ForegroundColor Yellow
    }

    # Try GitHub Actions secret
    if (-not $result.expected -and $env:INPUT_SSL_PIN_FINGERPRINT) {
        $result.expected = $env:INPUT_SSL_PIN_FINGERPRINT
        Write-Host "Read from input: $($result.expected.Substring(0, [Math]::Min(16, $result.expected.Length)))..." -ForegroundColor Yellow
    }
}

if (-not $result.expected) {
    $result.error = "No expected fingerprint found (not in .env, env var, or input)"
    $result.status = "no_expected"
    Write-Host ""
    Write-Host "ERROR: No expected fingerprint to compare against." -ForegroundColor Red
    Write-Host "  Provide via: -ExpectedFingerprint, .env file, or SSL_PIN_FINGERPRINT env var" -ForegroundColor Yellow
} else {
    # Validate format: should be 64 hex chars (SHA-256) or 40 hex chars (SHA-1)
    $cleaned = $result.expected -replace '[^0-9a-fA-F]', ''
    if ($cleaned.Length -eq 64) {
        $result.expected = $cleaned.ToLower()
    } elseif ($cleaned.Length -eq 40) {
        $result.expected = $cleaned.ToLower()
    } else {
        $result.error = "Invalid fingerprint format: expected 40 (SHA-1) or 64 (SHA-256) hex chars, got $($cleaned.Length)"
        $result.status = "invalid_format"
    }
}

# ── Extract actual certificate fingerprint ─────────────────────────────────────

if ($result.status -ne "unknown") {
    # Skip extraction if we already have a terminal status
} else {
    Write-Host ""
    Write-Host "Connecting to ${ApiHost}:443..." -ForegroundColor Cyan

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient($ApiHost, 443)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($ApiHost)

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)

        $result.actual_sha256 = $cert.GetCertHashString('sha256').ToLower()
        $result.actual_sha1 = $cert.GetCertHashString('sha1').ToLower()
        $result.cert_subject = $cert.Subject
        $result.cert_expires = $cert.NotAfter.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $result.days_until_expiry = ($cert.NotAfter - (Get-Date)).Days

        Write-Host "Certificate:" -ForegroundColor Green
        Write-Host "  Subject:   $($cert.Subject)"
        Write-Host "  Expires:   $($cert.NotAfter) ($($result.days_until_expiry) days)"
        Write-Host "  SHA-256:   $($result.actual_sha256)"
        Write-Host "  SHA-1:     $($result.actual_sha1)"

        $ssl.Close()
        $tcp.Close()
    } catch {
        $result.error = "Connection failed: $($_.Exception.Message)"
        $result.status = "connection_failed"
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── Compare fingerprints ──────────────────────────────────────────────────────

if ($result.status -eq "unknown" -and $result.actual_sha256) {
    $expectedClean = $result.expected -replace '[^0-9a-f]', ''

    # Match against SHA-256
    if ($expectedClean.Length -eq 64 -and $result.actual_sha256 -eq $expectedClean) {
        $result.match = $true
        $result.status = "match"
    }
    # Match against SHA-1
    elseif ($expectedClean.Length -eq 40 -and $result.actual_sha1 -eq $expectedClean) {
        $result.match = $true
        $result.status = "match"
    }
    else {
        $result.match = $false
        $result.status = "mismatch"
    }
}

# ── Output ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
if ($result.status -eq "match") {
    Write-Host " SSL PIN VERIFIED" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
} elseif ($result.status -eq "mismatch") {
    Write-Host " SSL PIN MISMATCH — CERT HAS CHANGED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected: $($result.expected)" -ForegroundColor Yellow
    Write-Host "Actual:   $($result.actual_sha256)" -ForegroundColor Red
    Write-Host ""
    Write-Host "To update, run:" -ForegroundColor Yellow
    Write-Host "  .\check_ssl_fingerprint.ps1 -UpdateEnv" -ForegroundColor White
    Write-Host ""
    Write-Host "Then update the SSL_PIN_FINGERPRINT repository secret:" -ForegroundColor Yellow
    Write-Host "  gh secret set SSL_PIN_FINGERPRINT - body '$($result.actual_sha256)'" -ForegroundColor White
} elseif ($result.status -eq "match" -and $result.days_until_expiry -lt 30) {
    Write-Host " SSL PIN OK — BUT CERT EXPIRES IN $($result.days_until_expiry) DAYS" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
} else {
    Write-Host " SSL CHECK: $($result.status)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
}

# ── Auto-update .env if requested ─────────────────────────────────────────────

if ($UpdateEnv -and $result.status -eq "mismatch" -and $result.actual_sha256) {
    $envPath = Join-Path $projectRoot ".env"
    if (Test-Path $envPath) {
        $content = Get-Content $envPath -Raw
        $newContent = $content -replace 'SSL_PIN_FINGERPRINT=\S+', "SSL_PIN_FINGERPRINT=$($result.actual_sha256)"
        Set-Content -Path $envPath -Value $newContent -NoNewline
        Write-Host ""
        Write-Host "Updated .env with new fingerprint." -ForegroundColor Green
    }
}

# ── Expiry warnings ───────────────────────────────────────────────────────────

if ($result.days_until_expiry -and $result.days_until_expiry -lt 30) {
    Write-Host ""
    Write-Host "WARNING: Certificate expires in $($result.days_until_expiry) days!" -ForegroundColor Yellow
    if ($result.days_until_expiry -lt 7) {
        Write-Host "CRITICAL: Less than 7 days until expiry!" -ForegroundColor Red
    }
}

# ── JSON output ───────────────────────────────────────────────────────────────

if ($OutputJson) {
    $json = $result | ConvertTo-Json -Depth 3
    Write-Host ""
    Write-Host "JSON Output:" -ForegroundColor DarkGray
    Write-Host $json
}

# ── Exit code ─────────────────────────────────────────────────────────────────

switch ($result.status) {
    "match"             { exit 0 }
    "mismatch"          { exit 1 }
    "connection_failed" { exit 2 }
    "no_expected"       { exit 3 }
    "invalid_format"    { exit 4 }
    default             { exit 0 }
}
