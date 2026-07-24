# Phase 4 — Manifest Enrichment

**Status:** Complete
**Date:** 2026-07-22
**Reviewer Rating:** Pending

---

## 1. Objective

The manifest must answer one question:

> **"Is this update allowed to install on this machine?"**

Prior phases answered "is there an update?" and "how do we install it?"
Phase 4 adds the **policy enforcement layer** that prevents invalid updates
from ever reaching the download pipeline.

---

## 2. What Changed

### 2.1 UpdateManifest v2 (`lib/models/remote_config.dart`)

The manifest model was enriched with six new fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `schemaVersion` | `int` | `1` | Manifest format version. Client rejects unknown schemas. |
| `channel` | `String?` | `"stable"` | Release channel: `stable`, `beta`, `internal`, `dev`. |
| `maximumVersion` | `String?` | `null` | Upper version ceiling (e.g. `"5.999.0"` blocks 6.0.0). |
| `minimumOsVersion` | `String?` | `null` | Minimum Windows version (e.g. `"10.0.19045"`). |
| `expiresAt` | `String?` | `null` | ISO-8601 expiry timestamp. |
| `signature` | `String?` | `null` | HMAC-SHA256 of the manifest payload. |

**Backward compatibility:** All new fields are nullable with safe defaults.
Old v1 manifests deserialize without error — `schemaVersion` defaults to `1`,
all other new fields default to `null`.

### 2.2 ManifestPolicy (`lib/core/update/manifest_policy.dart`)

Declarative constraint set constructed once at startup:

- `acceptedSchemaVersions` — which schema versions the client understands
- `boardChannel` — this device's release channel
- `allowedChannels` — additional channels this device may receive
- `windowsVersion` — current OS version tuple
- `installedVersion` — current app version
- `boardId` — device identifier
- `hmacSecretKey` — HMAC key for signature verification

### 2.3 ManifestValidator (`lib/core/update/manifest_validator.dart`)

Stateless policy enforcer. All methods are `static`. No shared state.

**Check order (all evaluated, not short-circuited):**

| # | Check | Failure Condition |
|---|---|---|
| 1 | Schema version | `manifest.schemaVersion` not in `acceptedSchemaVersions` |
| 2 | Expiry | `expiresAt` is in the past |
| 3 | Channel | Manifest channel not in board's allowed channels |
| 4 | Upgrade direction | `installedVersion >= manifest.minimumVersion` (not an upgrade) |
| 5 | Version ceiling | `installedVersion >= manifest.maximumVersion` |
| 6 | OS compatibility | `Platform.version < manifest.minimumOsVersion` |
| 7 | Rollout inclusion | Board hash not in rollout cohort (skipped when `force=true`) |
| 8 | HMAC signature | Computed HMAC ≠ manifest `signature` |

**Result:** `ManifestValidationResult` — `allowed: bool`, `reasons: List<String>`.

All failures are collected before returning. The caller sees every violation.

### 2.4 AutoUpdater Integration (`lib/services/auto_updater.dart`)

The policy check runs **after** dedup but **before** download:

```
checkForUpdate()
  → Guard: initialized?
  → Guard: 30s startup delay
  → Dedup: fingerprint match?
  → Phase 4: ManifestValidator.check(manifest, policy)  ← NEW
  → Guard: second update running?
  → Version comparison
  → Download URL present?
  → Disk space
  → Start update
```

The redundant rollout check (lines 264–269) was removed since
`ManifestValidator._checkRollout()` handles it.

`AutoUpdater.init()` now accepts optional `boardChannel` and
`hmacSecretKey` parameters (backward-compatible — defaults to `"stable"` and
`null`).

---

## 3. Server-Side Manifest Contract

```json
{
  "schema_version": 2,
  "channel": "stable",
  "minimum_version": "5.5.0",
  "maximum_version": "5.999.0",
  "minimum_os_version": "10.0.19045",
  "expires_at": "2026-12-31T23:59:59Z",
  "download_url": "https://cdn.example.com/iasb-5.5.0.msi",
  "sha256": "a1b2c3...",
  "signature": "hmac-sha256-of-all-fields-except-signature",
  "file_size": 19437568,
  "force": true,
  "rollout_percentage": 100,
  "release_notes": "Security patch for QR scanning module",
  "published_at": "2026-07-22T08:00:00Z"
}
```

### Field requirements:

| Field | Server MUST | Client behavior when absent |
|---|---|---|
| `schema_version` | send | Defaults to `1` |
| `channel` | send | Defaults to `"stable"` |
| `minimum_version` | send | Defaults to `"0.0.0"` (always update) |
| `download_url` | send | Client aborts (can't install without URL) |
| `sha256` | send | Client rejects (no unverified updates) |
| `expires_at` | send | No expiry check |
| `minimum_os_version` | omit if no constraint | No OS check |
| `maximum_version` | omit if no ceiling | No ceiling check |
| `signature` | send when HMAC configured | No signature check |

---

## 4. HMAC Signature Scheme

### Signing (server)

```python
import hmac, hashlib, json

payload = {k: v for k, v in manifest.items() if k != "signature"}
canonical = json.dumps(payload, separators=(',', ':'), sort_keys=True)
signature = hmac.new(secret_key.encode(), canonical.encode(), hashlib.sha256).hexdigest()
manifest["signature"] = signature
```

### Verification (client)

1. Extract `signature` from manifest
2. Remove `signature` from manifest JSON
3. Serialize remaining fields as canonical JSON
4. Compute HMAC-SHA256 with shared secret
5. Compare to extracted signature

**Implementation:** `ManifestValidator._checkSignature()` — see
`lib/core/update/manifest_validator.dart:163`.

---

## 5. Version Range Semantics

```
installedVersion < minimumVersion   →  UPDATE NEEDED
minimumVersion <= installedVersion   →  UP TO DATE (denied)
installedVersion >= maximumVersion   →  CEILING BLOCKED (denied)
```

Example: Board at `5.4.0`, manifest `minimum_version=5.5.0`,
`maximum_version=5.999.0`:
- `5.4.0 < 5.5.0` → update allowed ✓
- After update to `5.5.0`: `5.5.0 >= 5.5.0` → up to date ✓
- Board at `5.5.0`, manifest `maximum_version=5.5.0`:
  `5.5.0 >= 5.5.0` → ceiling blocked ✓

---

## 6. Channel Enforcement

| Board Channel | Manifest Channel | Allowed? |
|---|---|---|
| `stable` | `stable` | ✓ |
| `stable` | `beta` | ✗ |
| `stable` | `internal` | ✗ |
| `beta` | `stable` | ✓ |
| `beta` | `beta` | ✓ |
| `beta` | `internal` | ✗ |
| `internal` | `stable` | ✓ |
| `internal` | `beta` | ✓ |
| `internal` | `internal` | ✓ |

A board can also receive cross-channel updates via `allowedChannels`:

```dart
ManifestPolicy(
  boardChannel: 'stable',
  allowedChannels: {'stable', 'internal'},  // accept internal patches
)
```

---

## 7. Test Scenarios

### 7.1 Schema Rejection

- Schema version 99 → denied with "Schema version 99 not in accepted set"
- Schema version 2 → allowed (when supported)
- Schema version 1 → allowed (backward compatible)

### 7.2 Expiry

- `expires_at` = yesterday → denied with "Manifest expired"
- `expires_at` = tomorrow → allowed
- `expires_at` = null → allowed (no expiry)

### 7.3 Channel

- Board `stable`, manifest `beta` → denied
- Board `stable`, manifest `stable` → allowed
- Board `beta`, manifest `stable` → allowed (downgrade channel is OK)

### 7.4 Version Range

- Board `5.4.0`, manifest min `5.5.0` → allowed (upgrade)
- Board `5.5.0`, manifest min `5.5.0` → denied (up to date)
- Board `5.6.0`, manifest min `5.5.0` → denied (downgrade)
- Board `5.4.0`, manifest max `5.4.0` → denied (ceiling)
- Board `5.4.0`, manifest max `5.5.0` → allowed (under ceiling)

### 7.5 OS Compatibility

- Board `10.0.19041`, manifest min `10.0.19045` → denied
- Board `10.0.19045`, manifest min `10.0.19045` → allowed
- Board `10.0.22621`, manifest min `10.0.19045` → allowed (newer)
- Manifest min `null` → allowed (no constraint)

### 7.6 Rollout

- Board hash in 5% cohort, manifest rollout 5% → allowed
- Board hash outside cohort, manifest rollout 5% → denied
- `force=true` → bypass rollout check

### 7.7 HMAC Signature

- Valid signature → allowed
- Tampered signature → denied with "HMAC signature mismatch"
- Missing signature when key configured → allowed (no check)
- Signature present when key is null → allowed (no check)

---

## 8. Files Changed

| File | Action |
|---|---|
| `lib/models/remote_config.dart` | Modified — enriched UpdateManifest v2 |
| `lib/core/update/manifest_policy.dart` | **New** — constraint set |
| `lib/core/update/manifest_validator.dart` | **New** — policy enforcer |
| `lib/services/auto_updater.dart` | Modified — integrated validator |

---

## 9. Acceptance Criteria

- [x] `flutter analyze lib/` — zero new issues
- [x] ManifestPolicy constructed from AutoUpdater state at check time
- [x] ManifestValidator called before download, not after
- [x] All 8 checks evaluated (not short-circuited)
- [x] Backward compatible with v1 manifests
- [x] AutoUpdater.init() API is backward compatible (new params optional)
- [x] Redundant rollout check removed from AutoUpdater
- [x] HMAC verification uses canonical JSON serialization
- [x] Result includes all denial reasons (not just first)

---

## 10. Migration Notes

**Server-side:** Existing heartbeat responses with v1 manifests continue
working. The client treats `schema_version: 1` (or missing) as the legacy
format. To enable the new checks, the server must start including the new
fields.

**No breaking changes.** This is a purely additive enhancement.
