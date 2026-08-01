# Phase 1 Session Changelog — Update System Stabilization

**Branch:** `school-main` (v5.5.0+17, `fb27994`)
**Date:** 2026-08-01
**Companion report:** `docs/phase1_validation_report.md`

This changelog documents every code change made during the Phase 1 validation
effort, the defect each change fixes, and how it was verified. Nothing here is a
test-only weakening — every change either fixes a real production defect or
repairs a test fixture/harness bug.

---

## Production Changes

### 1. Disk-space probe no longer blocks updates on probe failure

**File:** `lib/services/auto_updater.dart` — `_hasEnoughDiskSpace()`

- **Defect:** `return diskSpaceProbeOverride!();` returns a `Future<bool>` from
  an `async` function. Dart flattens that into the surrounding future, so an
  error thrown by the probe surfaces **outside** the `try/catch` — a throwing
  disk probe blocked every update instead of failing open (the documented intent:
  *"updates are never blocked by a check failure"*).
- **Fix:** `return await diskSpaceProbeOverride!();` — the error is now caught,
  logged, and the check fails open (returns `true`, allowing the update).
- **Verified by:** disk-space block scenarios; `flutter analyze` clean.

---

### 2. Cancel mid-download now aborts the stream and removes the partial file

**File:** `lib/services/auto_updater.dart` — `_downloadWithProgress()`,
`_startUpdatePipeline()`; new `_DownloadCancelled` exception.

- **Defect (SC-026):** `dismiss()` closed the active HTTP client and called
  `File.deleteSync()`, but on Windows a file with an **open handle cannot be
  deleted** — the delete threw and was swallowed, leaving the partial installer.
  The download stream was also never explicitly aborted, and the failed/cancelled
  path could leave `progress` at `downloading`.
- **Fix:**
  - `_downloadWithProgress` checks `_dismissRequested` on **every chunk** and
    throws `_DownloadCancelled` immediately, so the stream stops draining.
  - The outer `finally` deletes the partial `destination` file **after** the
    sink has been closed (deletion is now legal on Windows).
  - Both dismissal paths in `_startUpdatePipeline` (post-download and
    catch) defensively delete the installer file before returning.
  - `dismiss()` continues to clear `progress.value` and keeps
    `availableUpdate` (Settings "Retry" persists).
- **Verified by:** SC-026 now passes (no orphan, overlay cleared,
  `availableUpdate` preserved).

---

### 3. Replayed manifest is deduplicated — no double install

**File:** `lib/services/auto_updater.dart` — `_startUpdate()`

- **Defect (SC-027, SC-083):** on pipeline **success**, `_startUpdate` cleared
  `_lastCheckedManifestFingerprint`. Re-delivering the identical manifest
  (`version|force|rollout`) then passed the dedup guard and started a second
  download/install pipeline.
- **Fix:** keep `_lastCheckedManifestFingerprint` after success, so a replay is
  rejected by the fingerprint dedup (line ~295 in `checkForUpdate`). The
  **failure** path still clears it, so a transient failure can be retried.
  Production is unaffected by the change because the "already up to date"
  version guard already covers the post-install case.
- **Verified by:** SC-027 (duplicate requests deduplicated) and SC-083
  (replayed valid manifest rejected) both pass.

---

### 4. Circuit breaker now opens after 3 consecutive failures

**File:** `lib/services/auto_updater.dart` — `checkForUpdate()`

- **Defect (SC-100):** the failed-state guard
  (`if (progress.state == failed && !force) → return false`, "waiting for user
  action") blocked **every** non-force re-check before the pipeline could fail
  a second time. Consecutive failures could therefore never accumulate, the
  circuit breaker never opened (3+ failure protection was dead code), and the
  Settings "Retry" button for a non-force update was a no-op.
- **Fix:** removed the failed-state guard block. The circuit breaker
  (`_incrementCircuitBreaker`, opens at `_maxConsecutiveFailures = 3`) is now
  the single anti-retry mechanism: the same manifest is attempted up to 3 times,
  then auto-retry stops until an admin re-push (WebSocket) or user Settings
  "Retry" resets it (`resetCircuitBreaker`).
- **Verified by:** SC-100 now passes — 3 failures attempted, breaker open on the
  4th check (returns `false`).

---

### 5. Update health state persists on fresh installs

**File:** `lib/services/update_health_monitor.dart` — `_saveToRegistry()`

- **Defect:** wrote `Data\update_health.json` without ensuring `Data\` existed.
  On a fresh install the directory is created later by the pipeline, so every
  early write failed with `PathNotFoundException` and the health state was
  silently dropped (observed as non-fatal warnings in every scenario run).
- **Fix:** `_prefsFile.parent.createSync(recursive: true);` before writing.
- **Verified by:** log noise eliminated across the full suite.

---

## Test Fixture / Harness Changes

### 6. Fault server reset mode now actually resets the connection

**File:** `test/validation/fault_http_server.dart` — `serveInstaller()`

- **Defect (SC-019):** the reset path called `resp.detachSocket()` **after**
  `resp.add(...)` had already sent the headers → `detachSocket()` threw
  `Bad state: Headers already sent`, the exception was swallowed, and the
  connection hung open. The client received 64 KB of a 256 KB body and waited
  forever — the scenario never failed and the pipeline never settled.
- **Fix:** in reset mode, detach the socket **before** writing any response
  bytes, then hand-craft the HTTP/1.1 response (headers + `resetAfterBytes`
  body bytes) over the raw socket and `destroy()` it — a genuine mid-body reset.
- **Verified by:** SC-019 now fails cleanly in ~55 ms (was a 20 s hang).

### 7. Validation report aggregates all scenarios

**File:** `test/validation/phase1_validation_test.dart` — `setUp()`

- **Defect:** `setUp()` called `ValidationSuite.reset()` before **every** test,
  wiping previously registered results. `tearDownAll` therefore reported only the
  last scenario (`GATE=FAIL executed=0 pending=1`) and the generated report was
  empty.
- **Fix:** removed the per-test reset; results now accumulate across all 115
  scenarios and the report is complete.
- **Verified by:** final run reports `executed=75 passed=75 failed=0 pending=40`.

### 8. Harness tests updated for the (corrected) dedup semantics

**File:** `test/validation/phase1_validation_test.dart`

- **"20 repeated downloads leave exactly one installer and no orphans"** —
  previously drove the identical manifest 20× expecting 20 pipelines. With the
  dedup fix (#3) a repeated identical manifest is correctly rejected, so each
  iteration now alternates the `force` flag (distinct fingerprint, same
  installer path) to simulate 20 distinct admin pushes. Leak/file assertions
  unchanged.
- **"Missing backup is recreated"** — the second drive now targets v5.6.0 (the
  *next* update, distinct fingerprint) instead of re-driving the v5.5.0 manifest,
  preserving the backup-recreation intent.

---

## Scope Note

The following are **unmodified** and unchanged from earlier sessions:
`lib/core/config/install_paths.dart`, `lib/services/update_agent_launcher.dart`,
`windows/inno_setup/setup.iss`, `windows/update_agent/main.cpp`,
`.github/workflows/auto-deploy.yml` appear in the working tree from prior work on
this branch, not from this validation session.
