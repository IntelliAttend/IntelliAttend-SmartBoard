# IntelliAttend SmartBoard — OTA Update System

## Overview

This document describes the fleet-aware OTA (over-the-air) update system implemented for production-grade rollout management. It covers the server-side changes (database models, API endpoints, heartbeat integration, CI/CD integration) and how the client-side auto-updater interacts with them.

### Architecture

```
CI/CD (GitHub Actions)
  │  POST /api/v1/board/ci-upload  (X-Deploy-Key auth)
  ▼
FastAPI Server ──→ release_manifests table (active release)
  │
  │  Heartbeat response includes force_update block
  ▼
SmartBoard (Flutter) ──→ auto_updater.dart downloads MSI
  │
  │  POST /api/v1/board/update-status  (Firebase Board auth)
  ▼
FastAPI Server ──→ board_versions table + update_events audit log
  │
  │  GET  /api/v1/admin/fleet   (Admin JWT)
  │  POST /api/v1/admin/board/{id}/update
  │  POST /api/v1/admin/board/{id}/rollback
  │  POST /api/v1/admin/rollback-all
  ▼
IT Dashboard (operations console)
```

---

## 1. New Database Models

### 1.1 `board_versions`

**File:** `backend/python/models/sql_models.py` (lines 462–500)

Single source of truth per-board version state. Upserted on every heartbeat and on every status report.

| Column | Type | Description |
|---|---|---|
| `board_id` | FK → users.id | Unique per board |
| `current_version` | varchar(32) | Version currently running on the board |
| `target_version` | varchar(32) | Version the admin pushed (null if idle) |
| `update_status` | varchar(32) | `idle` \| `downloading` \| `installing` \| `completed` \| `failed` \| `rolled_back` |
| `download_progress` | float | 0.0–1.0 |
| `last_update_at` | timestamptz | When the board last reported an update outcome |
| `last_heartbeat_at` | timestamptz | Last health check from the board |
| `last_error` | text | Last error message if status is `failed` or `rolled_back` |
| `rollback_count` | int | Total rollbacks this board has experienced |

### 1.2 `update_events`

**File:** `backend/python/models/sql_models.py` (lines 503–532)

Immutable append-only audit log. Every status report, admin push, and rollback creates a row.

| Column | Type | Description |
|---|---|---|
| `board_id` | FK → users.id | Which board |
| `event_type` | varchar(32) | `status_report` \| `admin_push` \| `admin_rollback` |
| `current_version` | varchar(32) | Version after the event |
| `previous_version` | varchar(32) | Version before the event |
| `target_version` | varchar(32) | Version being targeted |
| `status` | varchar(32) | `completed` \| `failed` \| `rolled_back` \| `pushed` \| `triggered` |
| `stable_startups` | int | Number of stable boots since last update (from the board) |
| `rollback_count` | int | Rollback counter at time of event |
| `error_message` | text | Error detail if applicable |

### 1.3 `release_manifests`

**File:** `backend/python/models/sql_models.py` (lines 535–558)

Stores release metadata uploaded by CI/CD. The `_build_board_config` function reads from this table to populate the heartbeat response.

| Column | Type | Description |
|---|---|---|
| `version` | varchar(32) | Semantic version (e.g. `5.6.0`) |
| `download_url` | text | Full GitHub Releases URL to the MSI |
| `sha256` | varchar(64) | Integrity hash (computed by CI) |
| `force` | boolean | Whether the board must install immediately |
| `rollout_percentage` | int | 0–100, for phased rollout |
| `release_notes` | text | Markdown release notes |
| `is_active` | boolean | Only one manifest is active at a time |
| `uploaded_by` | varchar(64) | `ci` or `admin` |

---

## 2. New Schemas

**File:** `backend/python/models/board_auth_schema.py` (lines 53–87)

| Schema | Purpose |
|---|---|
| `UpdateStatusReport` | Board → Server: reports `completed` / `failed` / `rolled_back` with version, stable_startups, rollback_count |
| `CiUploadRequest` | CI/CD → Server: uploads version, release_notes, force, rollout_percentage |
| `AdminUpdateRequest` | Admin → Server: pushes target_version, download_url, sha256, force, rollout_percentage to a board |
| `AdminRollbackRequest` | Admin → Server: target_version (optional — server infers previous if empty) + reason |

---

## 3. Database Migration

**File:** `backend/python/alembic/versions/004_add_update_tracking.py`

Run on the server database:

```bash
cd backend/python
alembic upgrade head
```

Creates all three tables with indexes on `board_id`, `update_status`, `event_type`, and `is_active`.

---

## 4. New API Endpoints

### 4.1 `POST /api/v1/board/update-status` (Board → Server)

**Auth:** Firebase Board token (same as heartbeat)

**Purpose:** The board calls this after completing, failing, or rolling back an auto-update.

**Request body:**
```json
{
  "current_version": "5.6.0",
  "previous_version": "5.5.0",
  "status": "completed",
  "stable_startups": 15,
  "rollback_count": 0,
  "timestamp": "2026-07-16T10:30:00Z"
}
```

**Server behavior:**
- Upserts `board_versions` (current_version, update_status, last_update_at, rollback_count)
- Appends `update_events` audit row (event_type=`status_report`)
- If status is `completed`, clears target_version and sets download_progress=1.0
- If status is `failed` or `rolled_back`, records last_error

**Client integration:** Called from `auto_updater.dart` at the end of each update attempt. See `lib/services/auto_updater.dart:340-358` for the SHA-256 enforcement, and the `_reportOutcome` method that POSTs to this endpoint.

---

### 4.2 `POST /api/v1/board/ci-upload` (CI/CD → Server)

**Auth:** `X-Deploy-Key` header matching `DEPLOY_KEY` env var

**Purpose:** GitHub Actions calls this after building an MSI to register the release.

**Parameters (multipart form):**
| Field | Type | Description |
|---|---|---|
| `version` | string | Required. Flutter version (e.g. `5.6.0`) |
| `release_notes` | string | Optional markdown |
| `force` | string | `"true"` or `"false"` |
| `rollout_percentage` | string | `"0"`–`"100"` |
| `file` | file | Optional MSI binary |

**Server behavior:**
- Deactivates any previous active manifest
- Creates a new `ReleaseManifest` row with `is_active=true`
- Builds download_url from `https://github.com/{repo}/releases/download/v{version}/{name}-{version}.msi`

**CI integration:** `auto-deploy.yml` (lines 191–211) calls this endpoint after creating the GitHub Release.

---

### 4.3 `POST /api/v1/admin/board/{board_id}/update` (Admin → Board)

**Auth:** Admin JWT (`require_role(["admin"])`)

**Purpose:** Push an update to a specific board via WebSocket.

**Request body:**
```json
{
  "target_version": "5.6.0",
  "download_url": "https://github.com/.../release.msi",
  "sha256": "abc123...",
  "force": true,
  "rollout_percentage": 100,
  "release_notes": "Bug fixes"
}
```

**Server behavior:**
- Upserts `board_versions` with target_version and update_status=`downloading`
- Logs audit event (event_type=`admin_push`)
- Sends `update_available` WebSocket message to the board
- If board is offline, queues the command for delivery when it reconnects

**WebSocket message payload:**
```json
{
  "type": "update_available",
  "command_id": "<uuid>",
  "manifest": { ... },
  "issued_at": "2026-07-16T..."
}
```

---

### 4.4 `POST /api/v1/admin/board/{board_id}/rollback` (Admin → Board)

**Auth:** Admin JWT

**Purpose:** Trigger a rollback on a specific board to a previous version.

**Request body:**
```json
{
  "target_version": "5.5.0",   // optional — server infers if empty
  "reason": "v5.6.0 has a critical display bug"
}
```

**Server behavior:**
- If target_version not provided, queries the last `status_report` event to find the previous version
- Updates board_versions with target_version and update_status=`rolling_back`
- Logs audit event (event_type=`admin_rollback`)
- Sends `update_available` WebSocket message with `force: true` and the rollback target

---

### 4.5 `POST /api/v1/admin/rollback-all` (Admin → Fleet)

**Auth:** Admin JWT

**Purpose:** Emergency fleet-wide rollback. Creates a new active manifest pointing to the rollback version.

**Request body:** Same as `AdminRollbackRequest`

**Server behavior:**
- Deactivates all active release manifests
- Creates a new `ReleaseManifest` with the rollback version, `force=true`, `rollout_percentage=100`
- Updates every `BoardVersion` row to target the rollback version
- Logs audit events for every board
- Returns `{ "status": "ok", "target_version": "...", "boards_affected": N }`

---

### 4.6 `GET /api/v1/admin/fleet` (IT Dashboard)

**Auth:** Admin JWT

**Purpose:** Returns complete fleet version dashboard data.

**Response:**
```json
{
  "status": "ok",
  "total_boards": 42,
  "version_distribution": {
    "5.5.0": 30,
    "5.6.0": 10,
    "unknown": 2
  },
  "status_distribution": {
    "idle": 35,
    "downloading": 2,
    "installing": 1,
    "completed": 3,
    "failed": 1,
    "rolling_back": 0
  },
  "active_release": {
    "version": "5.6.0",
    "force": true,
    "rollout_percentage": 100,
    "created_at": "2026-07-16T..."
  },
  "boards": [
    {
      "board_id": "IASB-4208",
      "current_version": "5.5.0",
      "target_version": "5.6.0",
      "update_status": "downloading",
      "download_progress": 0.45,
      "last_heartbeat_at": "2026-07-16T10:30:00Z",
      "last_update_at": "2026-07-15T14:00:00Z",
      "last_error": null,
      "rollback_count": 0
    }
  ]
}
```

---

## 5. Heartbeat Integration

Every heartbeat (`POST /api/v1/board/heartbeat` in `main.py:325-371`) now:

1. Records the heartbeat as before in `BoardHeartbeat`
2. **Upserts `board_versions`** with `current_version = request.appVersion` and `last_heartbeat_at = now`
3. Calls `_build_board_config(board_id, pg_session)` which:
   - Queries `release_manifests` for the active manifest
   - If found, includes `force_update` block in the response config
   - Falls back to environment variables (`UPDATE_MINIMUM_VERSION`, etc.) if no DB manifest exists

This means every 15-second heartbeat also serves as a version inventory check — the fleet dashboard always knows what's running on each board.

---

## 6. `_build_board_config` Changes

**File:** `backend/python/main.py` (lines 374–446)

Previously read update configuration solely from environment variables. Now:

1. Checks `release_manifests` table for an active CI-uploaded manifest
2. If found, uses it as the `force_update` block in the board config
3. If not found (or on error), falls back to env vars for backward compatibility

The `GET /api/v1/board/config` endpoint also calls this function, so boards receive the correct update manifest regardless of how they fetch config.

---

## 7. Client-Side: SHA-256 Mandatory

**File:** `lib/services/auto_updater.dart` (lines 347–358)

Previously, a missing `sha256` in the manifest would log a warning and skip verification. Now it **refuses to install**:

```dart
// SHA-256 is mandatory — reject updates without a hash.
Log.e('[AutoUpdater] No SHA-256 in manifest — refusing to install unverified update');
```

This ensures every update delivered to a board is cryptographically verified.

---

## 8. CI/CD Changes

### 8.1 `auto-deploy.yml`

| Change | Description |
|---|---|
| Removed `|| true` from dart analyze | CI now fails on lint errors |
| Added `flutter test` step | Unit tests run before building |
| Added MSI signing | Uses `WIX_SIGN_CERT_BASE64` + `WIX_SIGN_PASSWORD` secrets if available |
| Computes SHA-256 | Written to `{name}-{version}.sha256` and uploaded as release asset |
| Version manifest | Creates `latest.json` with version, download_url, sha256, force, rollout_percentage |
| Deploy key auth | Calls `POST /api/v1/board/ci-upload` with `X-Deploy-Key` header |

### 8.2 `release.yml`

| Change | Description |
|---|---|
| Added Authenticode signing step | Decodes `WIX_SIGN_CERT_BASE64`, signs MSI, cleans up cert file |
| Added SHA-256 computation | Written to file and exposed as step output |
| SHA-256 printed in release body | Verification hash visible on the GitHub Release page |

---

## 9. Operational Notes

### Deploying the Migration

```bash
cd backend/python
alembic upgrade head
```

This creates `board_versions`, `update_events`, and `release_manifests` tables. Existing boards will appear in the fleet dashboard on their next heartbeat (a `board_versions` row is created automatically by the heartbeat endpoint).

### Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `DEPLOY_KEY` | For CI upload | Shared secret between GitHub Actions and the server |
| `WIX_SIGN_CERT_BASE64` | Optional | Base64-encoded Authenticode certificate for MSI signing |
| `WIX_SIGN_PASSWORD` | Optional | Certificate password |

### Rollout Process

1. Push to `school-main` → GitHub Actions builds MSI, creates release, calls `ci-upload`
2. Boards detect new manifest on next heartbeat (or immediately if connected via WebSocket)
3. Auto-updater downloads, verifies SHA-256, installs, and restarts
4. Board reports outcome via `POST /api/v1/board/update-status`
5. IT Dashboard at `GET /api/v1/admin/fleet` shows real-time status

### Emergency Rollback

```bash
# Single board
curl -X POST https://api/admin/board/IASB-4208/rollback \
  -H "Authorization: Bearer <admin_jwt>" \
  -d '{"reason": "critical display bug"}'

# Fleet-wide
curl -X POST https://api/admin/rollback-all \
  -H "Authorization: Bearer <admin_jwt>" \
  -d '{"target_version": "5.5.0", "reason": "v5.6.0 regression"}'
```

### Missing Features (Future)

- Maintenance windows (don't update during class hours)
- Phased rollout (1 board → 5 → all)
- Download resume for large MSIs over weak connections
- Push notifications to IT on failed rollback

---

## 10. File Reference

| File | What Changed |
|---|---|
| `backend/python/main.py` | 6 new endpoints, `_build_board_config` made async + DB-aware, heartbeat upserts `board_versions` |
| `backend/python/models/sql_models.py` | 3 new tables: `BoardVersion`, `UpdateEvent`, `ReleaseManifest` |
| `backend/python/models/board_auth_schema.py` | 4 new schemas: `UpdateStatusReport`, `CiUploadRequest`, `AdminUpdateRequest`, `AdminRollbackRequest` |
| `backend/python/alembic/versions/004_add_update_tracking.py` | New migration creating all 3 tables |
| `lib/services/auto_updater.dart` | SHA-256 verification now mandatory — rejects updates without hash |
| `.github/workflows/auto-deploy.yml` | Fixed analyzer, added tests, MSI signing, `ci-upload` call |
| `.github/workflows/release.yml` | Added Authenticode signing step |
