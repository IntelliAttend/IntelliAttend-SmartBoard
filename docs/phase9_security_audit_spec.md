# Phase 9 — Security Audit Specification

**Version**: 1.0  
**Status**: Complete  
**Phase**: 9 of 12  
**Architecture Freeze**: Applies (only security fixes accepted)

---

## 1. Scope

Full-source security audit of the IntelliAttend SmartBoard codebase (100+ Dart files, C++ update agent, PowerShell scripts, build configs, installer). Assessed attack surfaces: hardcoded secrets, network transport, file system, input validation, cryptography, registry access, process execution, secure storage.

---

## 2. Summary

| Severity | Count | Remediation Status |
|----------|-------|--------------------|
| **High** | 3 | Remediation recommended (S-01 requires infra action) |
| **Medium** | 9 | Remediation recommended |
| **Low** | 9 | Track for future hardening |
| **Info** | 10 | Positive findings + minor improvements |
| **Total** | **31** | |

---

## 3. High Severity Findings

### S-01 | Hardcoded Secrets in `.env` and Git History

- **File:** `.env` (lines 3-7)
- **Description:** Production Firebase credentials (API key `AIzaSyBooFadQf3TZFvZOUJkihMUdgexrbeoQnE`, project ID, app ID) exist in `.env`. File is in `.gitignore` and was removed from tracking (commit `9df38fb`), but secrets remain in git history (commits `df4f026`, `b7cd086`, `c4c630a`).
- **Remediation:** (1) Delete `.env` from working directory. (2) Purge secrets from git history via BFG Repo-Cleaner or `git filter-repo`. (3) **Rotate the Firebase API key** — it is compromised in git history. (4) For CI/CD, inject via platform secrets (GitHub Actions, Azure DevOps variable groups).
- **Owner:** DevOps / Platform team
- **Priority:** Critical — requires key rotation

### S-02 | Hardcoded Firebase API Key in Source Code (Two Locations)

- **File:** `lib/core/config/app_config.dart:13-14`, `lib/core/config/enterprise_deploy_config.dart:146,155`
- **Description:** The same Firebase API key is hardcoded as a `static const` fallback in `app_config.dart` and as default parameter values in `FirebaseConfig` constructor and `fromJson`. These compile into the release binary and can be extracted.
- **Remediation:** Remove hardcoded values. Load exclusively from `deploy_config.json` or `env.json` at runtime. For fresh installs, retrieve from a server endpoint during registration. At minimum, ensure Firebase API key is restricted in Firebase Console to only required APIs (Identity Toolkit, Secure Token) and platform type Windows.
- **Owner:** Backend + Desktop team
- **Priority:** High

### S-03 | PowerShell Injection via Incomplete String Escaping in Hotspot Configuration

- **File:** `lib/services/hotspot_service.dart:267-276`
- **Description:** SSID and password are interpolated into a PowerShell script with only single-quote escaping. Backtick sequences (`` `n `` for newline), `$()` subexpression evaluation, and double-quoted string expansion are not blocked. If an attacker controls the SSID/password (compromised config or MITM on config delivery), they could inject arbitrary PowerShell.
- **Remediation:** Use `-EncodedCommand` with base64-encoded script blocks. Alternatively, validate that SSID and password contain only printable ASCII and no PowerShell metacharacters (`$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `|`, `&`).
- **Owner:** Desktop team
- **Priority:** High

---

## 4. Medium Severity Findings — SSL Pinning Gaps

All medium findings share a common theme: **defense-in-depth SSL pinning bypass**. The `SslPinningService` is correctly implemented (S-24) but several HTTP clients create their own `http.Client()` or `Dio()` without using it.

| Finding | File | Bypass | Recommendation |
|---------|------|--------|----------------|
| **S-04** | `firebase_rest_auth.dart:25` | Firebase REST auth calls | Replace `http.Client()` with `SslPinningService.client` |
| **S-05** | `token_manager.dart:42` | Token refresh calls | Replace `http.Client()` with `SslPinningService.client` |
| **S-06** | `document_service.dart:13` | Document downloads | Configure Dio with SSL-pinned adapter |
| **S-07** | `network_info_service.dart:175-176` | Speed test download | Use SSL-pinned client |
| **S-08** | `auto_updater.dart:452` | MSI update download | Use `SslPinningService.client` |
| **S-09** | `auth_interceptor.dart:56` | 401 token replay | Create replay Dio with SSL-pinned adapter |
| **S-10** | `hotspot_service.dart:329-332` | Password with spaces breaks netsh | Validate SSID/password format (8-63 printable ASCII, no spaces) |

**Recommended fix pattern:**
```dart
// Before (insecure)
final client = http.Client();
// or
final dio = Dio();

// After (pinned)
final client = SslPinningService.client;
// or
final dio = Dio(BaseOptions(...))
  ..httpClientAdapter = SslPinningService.pinnedAdapter;
```

**Priority:** Medium — SSL pinning is correctly implemented; these are gaps in adoption.

---

## 5. Low Severity Findings

| Finding | File | Description | Recommendation |
|---------|------|-------------|----------------|
| **S-11** | `network_info_service.dart:178` | HTTP (not HTTPS) speed test URL | Switch to `https://speedtest.tele2.net/1MB.zip` |
| **S-12** | `update_health_monitor.dart:395-397` | Predictable rollback script temp path | Use UUID filename, restrict permissions |
| **S-13** | `hotspot_service.dart:43` | Predictable hotspot script temp path | Use UUID filename, consider piped stdin |
| **S-14** | `session_manager.dart:17-20,35-38` | AES key generated but Isar encryption not used | Apply OS file permissions; document limitation |
| **S-15** | `secure_storage_service.dart:197-209` | `clearAll()` misses `session_secret_*` and `board_manifest_hash` | Add missing keys; consider tracked-list deletion |
| **S-16** | `api_client.dart:27-32` | LogInterceptor logs full request bodies (passwords, OTPs) | Disable body logging in production; add redaction patterns |
| **S-17** | `websocket_service.dart:653` | Raw WS messages logged on parse failure may leak secrets | Truncate to 200 chars before logging |
| **S-18** | `deploy_config_validator.dart:153-156` | Missing SSL pin is warning, not error | Make blocking error for production |
| **S-19** | `deploy_config_validator.dart:190-193` | Missing HMAC secret is warning, not error | Make blocking error for production; disable auto-updates if missing |

---

## 6. Info (Positive Findings)

These findings confirm that key security controls are correctly implemented:

| Finding | Description |
|---------|-------------|
| **S-24** | SSL certificate pinning correctly implemented with SHA-256 + SHA-1 fallback, mandatory in release mode |
| **S-25** | SHA-256 file integrity verification for update downloads; unhashed updates rejected |
| **S-26** | HMAC-SHA256 manifest signature verification prevents tampered updates |
| **S-27** | DPAPI secure storage correctly used for all sensitive data with retry logic |
| **S-28** | JWT and session secret redaction in application logs |
| **S-29** | Single-instance guard with PID liveness check prevents dual-instance corruption |
| **S-30** | End-to-end update integrity (SHA-256 file + HMAC-SHA256 manifest) |
| **S-31** | Hardware fingerprint uses SHA-256; raw identifiers never stored/logged/transmitted |

**Info (minor improvements):**

| Finding | Description | Recommendation |
|---------|-------------|----------------|
| **S-20** | Firebase REST error responses may log full response bodies | Log only status code + error message |
| **S-21** | HMAC signature comparison is not constant-time | Implement constant-time comparison |
| **S-22** | 18 parallel PowerShell processes for hardware fingerprint | Consider WMI/CIM via FFI for reduced latency |
| **S-23** | Power command service executes shutdown/restart | No action — commands are hardcoded, WebSocket channel authenticated |

---

## 7. Remediation Priority Matrix

| Priority | Findings | Effort | Impact |
|----------|----------|--------|--------|
| **P0 — Before Production** | S-01 (rotate key), S-02 (remove hardcoded keys), S-03 (PowerShell injection) | Medium | Critical attack surface reduction |
| **P1 — Before Pilot** | S-04–S-09 (SSL pinning gaps), S-10 (hotspot validation) | Low-Medium | Defense-in-depth |
| **P2 — Before RC3** | S-11–S-19 (low severity) | Low | Hardening |
| **P3 — Backlog** | S-20–S-23 (info/minor) | Low | Best practices |

---

## 8. Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All 31 findings documented with severity, file, line, description, recommendation | ✅ |
| 2 | High-severity findings have clear remediation steps | ✅ |
| 3 | SSL pinning gaps catalogued with fix pattern | ✅ |
| 4 | Positive findings confirm key security controls are solid | ✅ |
| 5 | Remediation priority matrix provided (P0–P3) | ✅ |
| 6 | Architecture freeze maintained — no new layers introduced | ✅ |
