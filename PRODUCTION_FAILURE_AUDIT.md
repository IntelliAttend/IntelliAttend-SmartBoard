# PRODUCTION FAILURE-HANDLING AUDIT — IntelliAttend SmartBoard

**Audit Date:** Sep 12, 2026
**Scope:** Client-side (Flutter kiosk) stability, failsafe mechanisms, failure UI, and loop/crash risk — "what fails, how it fails today, what it should do."
**Auditor(s):** opencode (automated code audit)
**Companion doc:** `PRODUCTION_READINESS_AUDIT.md` (broad ecosystem audit, Jul 2026)

> All findings verified against source with `file:line` evidence.

---

## 1. "Defer the UI, but not the server" — the biggest gap — **HIGH**

**Scenario:** Class slot ends while the teacher is still marking students on Attendance (or is on Workspace). The design deliberately does not rip the user away from the screen — a good intention.

**How it fails today:**
- T-1 / auto-close / heartbeat all *defer the UI transition* but **still fire `SessionLifecycle.end()` → which immediately kills the server session** (`lib/services/session_lifecycle.dart:105-114`). The teacher keeps using a screen the app renders as active, but every subsequent submit hits a **terminated session** server-side.
- Failed submits are queued to the offline drain, whose banner promises *"Will be submitted automatically when connection is restored"* (`lib/presentation/screens/attendance_screen.dart:388-395`), while `SyncManager` retries **10× then silently drops** the row (see §4). The teacher is told a promise that is false for a closed/invalid session.
- The T-1 deferral *marks the slot as fired* (`lib/core/platform/window_orchestrator_service.dart:174`), which **suppresses auto-close** at real slot end (`:232`) — the board can sit on a "live-looking" screen behind a dead server session indefinitely.

**What it should do:** deferring the UI must also defer the server terminate. Slot end should put Attendance into an explicit "TIME EXPIRED — submit now" state (graceful closure, not a silent kill). Never mark a slot as fired unless a termination actually occurred; auto-close must remain the backstop.

**Risk:** real attendance data-loss path with a misleading success toast.

---

## 2. Heartbeat can force-end a live session on a transient server 5xx — **HIGH**

**Scenario:** Server has a momentary 5xx, or the load balancer interrupts a single beat.

**How it fails today:**
- `ApiService` returns a final 5xx as a *normal* response (`lib/services/api_service.dart:167-176`), so `sendHeartbeatV2` yields `status:'error'` instead of throwing.
- In `lib/services/heartbeat_service.dart:203-218`, `isServerError` **bypasses the 3-beat grace period**. One bad beat force-ends the local session (`EndReason.heartbeatNull`) instantly — with **no user explanation** — whenever the teacher is not on the Attendance screen.
- Pre-existing guard: deferral while `BoardState.active` (user actively marking) exists at `heartbeat_service.dart:211-215` — correct, but everything else is not protected.

**What it should do:** a transport/`status:'error'` beat must never be interpreted as "session is null." Force-ends require N consecutive *successful* beats that genuinely report `session: null`, and should defer whenever any screen is active, show one in-app notice, and offer a path back.

**Risk:** silent mid-class session teardown.

---

## 3. WebSocket reconnect loop that never backs off — **HIGH**

**Scenario:** Server accepts the WS handshake then drops the connection instantly (half-open proxy / load-balancer restart).

**How it fails today:**
- `_reconnectAttempt` is **reset to 0 on every successful handshake** (`lib/services/websocket_service.dart:508-511`).
- Connect → drop → reconnect → attempt 0 → ~1s → repeat **forever**; the exponential backoff (`:918-948`) never engages because the counter keeps resetting.

**What it should do:** reset the counter only after the connection has been healthy for a minimum period (e.g., 30s). Count a connect-success-that-dies-fast as a failure. Cap the loop and show a subtle "reconnecting…" indicator rather than silent churn.

**Risk:** endless network churn; WS-driven session events delayed.

---

## 4. Duplicate / lost attendance in the offline queue — **HIGH**

**Scenario:** Slow server response on submit, or a partial local (Isar) failure.

**How it fails today:**
- `lib/services/sync_manager.dart:127-149`: the POST **and the Isar delete share one try/catch**. If the POST succeeds but the delete throws, the catch re-queues the row → **duplicate submission** unless the server dedupes.
- `lib/services/api_service.dart:177-184`: a timeout re-POSTs up to 3× a payload the server may have already processed.
- `lib/presentation/screens/attendance_screen.dart:417-426`: re-queue **resets `retryCount` and `createdAt`**, so the "drop after 10 retries / 24h" guard keeps getting pushed out — one payload can silently retry for days.
- When the drain finally drops the row, feedback is a snackbar on a workspace screen that may not be mounted (`lib/presentation/screens/workspace_screen.dart:236-238`) — otherwise **silent data loss**.
- `lib/services/heartbeat_service.dart:88-89`: `stop()` clears the pending-termination queue; a restart mid-outage loses it (memory, not persisted).

**What it should do:** isolate the delete from the POST; make submit idempotent client-side with a stable per-session `source_id`; make retry counters monotonic; persist the pending queue so restarts don't drop it; always surface a **persistent** (not snackbar) notice when a submission is permanently abandoned.

**Risk:** data integrity + silent loss.

---

## 5. Crash / startup / recovery — **HIGH**

**Scenario:** Any unhandled error, Isar/DB failure, or crash loop at boot.

**How it fails today:**
- `lib/main.dart:203-216`: an error before `runApp` (e.g., `ObservabilityManager.init`) leaves **no window and no recovery screen** — an invisible board. The 60s watchdog then finds `navigatorKey.currentState == null` (`lib/main.dart:315-340`) and fails to render anything.
- `lib/services/update_health_monitor.dart`: `_performRollback()` — the **anti-bricking rollout rollback — is never called from anywhere**. After an update crash-loop, the new version keeps failing; there is no auto-rollback.
- `lib/core/recovery/recovery_manager.dart:70,158-168`: `integrityFailure` / `lifecycleFailure` / `startupTimeout` have **no "Launch Anyway"** — the board is wedged on RecoveryScreen until a human acts. `lib/core/startup_service.dart:111-122` meanwhile **unregisters auto-start after 2 failed starts**, so the board stops booting itself.
- `lib/core/recovery/recovery_manager.dart:119-147`: auto-recovery relaunches unconditionally after cleanup without verifying the fix — can reboot into the same failure.

**What it should do:** a kiosk must *always* end on some full-screen, self-describing state — pre-`runApp` requires a native-layer watchdog (C++ runner) restart plus a bare fallback screen. RecoveryScreen should offer "Retry" / "Start anyway" / "Call IT" for **every** failure type. Wire the dead rollback; make auto-start drift recoverable by a human/local remote.

**Risk:** bricked / invisible boards.

---

## 6. Popups & error UI hygiene — **MEDIUM**

**How it fails today:**
- Overlay stack (`lib/main.dart:649-657`) is well built — admin / Emergency / Priority-One overlays have countdowns + acknowledgement. Good.
- `idle_screen` `_errorMessage` is **never auto-dismissed** (`:1662`, etc.) — one transient error becomes a permanent red banner; the purely informational "System sync delayed" renders in error red all class long (`:1135`).
- `boot_screen.dart:237` "Security Authorization Required" is `barrierDismissible: false` — the only truly un-exit-able modal (admin-only, rare).
- Several `unawaited()` futures can escape to the global zone handler with no `catchError`: heartbeat `checkNow()` (`lib/services/heartbeat_service.dart:151,242`), settings `checkForUpdate` (`lib/presentation/screens/settings_screen.dart:1029,1054`), and the DB migration bridge (`lib/main.dart:291`).

**What it should do:** auto-clear transient errors after ~5s; keep informational state out of error styling; wrap every remaining fire-and-forget in `catchError`; avoid permanent red banners for self-healing conditions.

---

## 7. Silent stale-state holes — **MEDIUM**

- **Stale `IDLE` bypasses every timer:** a session persisted to Isar while the WS was down is deliberately *not* applied to the state machine (`lib/services/session_state_service.dart:235-243`). T-1 / auto-close / safety-net all gate on `isActive`, so they **skip it**; only heartbeat/server discovery reconcile it — a phantom session can sit unmanaged until connectivity returns.
- **Orchestrator stall:** the 10s orchestrator tick awaits `ensureFullscreen()` (a hung `isFullScreen()` platform call on hotplug/sleep) first; the `_isTickRunning` guard then **freezes all slot logic** — T-0, T-1, auto-close, safety-net — because a hang is not a throw (`lib/core/platform/window_orchestrator_service.dart:78,100`).

**What it should do:** run the fullscreen health check as a parallel best-effort with its own timeout, never as the gate for slot timers; add a periodic "reconcile Isar session vs server" pass that runs even when the machine state is `IDLE`.

---

## 8. Additional smaller findings — **LOW**

| # | Finding | Evidence |
|---|---------|----------|
| 8.1 | Re-queue resets give-up guards (see §4) | `attendance_screen.dart:417-426` |
| 8.2 | Terminate can be re-fired from lifecycle AND heartbeat queue with no shared in-flight lock (dedup window only 5s) | `session_lifecycle.dart:56,152-163`; `heartbeat_service.dart:48-54,103-122` |
| 8.3 | Pending-termination retry counting races under stacked `_send()` loops → premature give-up (~5 beats instead of 10) | `heartbeat_service.dart:110-121` |
| 8.4 | Terminate retry exhaustion is log-only — server never told, user never warned | `session_orchestrator_screen.dart:263-268` |
| 8.5 | Breaker `onStateChanged`, WS `onConnectionState`, heartbeat `onSessionUpdate` are defined but have **zero listeners** — connectivity state never reaches the UI | `circuit_breaker.dart:24,59`; `websocket_service.dart:345`; `session_state_service.dart:133`; `heartbeat_service.dart:56-59` |
| 8.6 | On reconnect after outage, all N pending items flush back-to-back with 4 attempts each — up to 4N POSTs in seconds (thundering herd); only the circuit breaker throttles | `sync_manager.dart:91-150` |
| 8.7 | QueuedScan flush has no retry cap, no expiry — retries forever every 15s (latent; no current producer) | `sync_manager.dart:156-201` |
| 8.8 | 10s network probe downloads 1MB over plain HTTP from a public speed-test server whenever "online" | `network_info_service.dart:71-76,173-194` |
| 8.9 | `transport`-error resolving to `'status':'error'` misrepresents a server outage as "no session" | `api_service.dart:496-497` |
| 8.10 | Stale comment: heartbeat documented "every 5 minutes", actual cadence 15s | `api_service.dart:466` |
| 8.11 | `SummaryScreen` awaits an Isar write before its countdown — a hung write leaves the screen with no exit | `summary_screen.dart:41-55` |
| 8.12 | Client-side PIN `RateLimiter.recordAttempt` is never called — lock-out is server-only (per-faculty, 5/15min) | `core/rate_limiter.dart:30-37` |

---

## What is already good (no change)

- Kiosk self-heal + re-assert on unhandled errors (`KioskService.handleUnhandledError`, `ensureFullscreen` self-heal) — the taskbar can no longer stick.
- Popdown queue strictly auto-dismissing; `_showAttendanceNotification` bounded (4–5s).
- Per-endpoint circuit breaker, 30s HTTP timeouts, bounded exponential retries on direct API calls.
- Summary→Idle rediscovery prevented by `markRecentlyCompleted` cooldown; warm-up re-trigger guarded; orchestrator per-slot dedupe.
- Admin kill-switch (`executeAdministrativeShutdown` → `forceRelease`) works even mid-kiosk.
- Session ignition / PIN entry → server-per-faculty rate limiting protects against the "burn the bucket" lockout attack.

---

## Recommended priority

| # | Fix | Domain |
|---|-----|--------|
| 1 | Defer the server terminate with the UI; never mark T-1 fired unless truly terminated; "TIME EXPIRED — submit now" state | §1 |
| 2 | `status:'error'` heartbeat must never force-end; require N clean guaranted null beats + user-visible reason | §2 |
| 3 | Split POST vs delete in the offline drain; monotonic retry counters; persist pending queue; never drop silently | §4 |
| 4 | Reset WS `_reconnectAttempt` only after a healthy period | §3 |
| 5 | Wire the dead update rollback; "Launch Anyway" for all failure types; native watchdog for pre-`runApp` | §5 |
| 6 | Non-blocking fullscreen health check; stale-Isar reconciliation pass | §7 |
| 7 | Error-banner auto-dismiss; `catchError` on all fire-and-forget futures | §6 |

---

## Known fixes applied before this audit (Sep 2026)

- Kiosk no longer permanently releases on unhandled errors: `main.dart` zone handler re-asserts kiosk via `KioskService.handleUnhandledError()` and only marks launch-failed while startup is incomplete; `ensureFullscreen()` self-heals a mid-run force-release.
- `SessionLifecycle.end()` gained `forceTransition` so minimized slot-end / auto-close paths eliminate the session locally without depending on the WS broadcast.
- PIN entry is PIN-only (OTP toggle and 4-digit OTP branch removed).
- Dead WS senders `submitAttendance` / `saveDraft` removed.

---

## ✓ Focused core-flow fixes applied (Sep 12, 2026) — analyzer clean, 203 tests pass

Scope: daily core flow **session starting (PIN) → attendance → terminating**. Tracked in `TODO.md` #61–67.

| Fix | What changed |
|-----|--------------|
| **§1 Defer server terminate with the UI** | `SessionLifecycle.end()` deferral branch no longer fires the terminate — the server session stays alive so the teacher's later submissions keep working; no dedup lease held, so the teacher's End Session is never blocked. T-1 only marks the slot "fired" when termination actually happens, leaving the auto-close backstop intact at slot end. |
| **§2 Heartbeat never force-ends on transport error** | `status:'error'`/5xx beats are ignored entirely — never counted toward the null-session threshold, never end a live session. Only 3 consecutive *clean* null-session responses can force-end (and even then, never while `BoardState.active`). |
| **§4 Offline queue integrity** | Isar delete split out of the submit try/catch (`sync_manager.dart`) so a local delete failure can't re-submit a synced payload or inflate retries; `attendance_screen.dart` re-queue preserves `retryCount`/`createdAt`. Server `/session/attendance/submit` confirmed idempotent (`on_conflict_do_update` on session_id+student_id). |
| **§8.2/8.3 Terminate in-flight lock** | Heartbeat `_send()` serialized behind `_isSendRunning` (overlapping beats dropped); `SessionLifecycle` dedup lease held until the terminate settles (6 min when handed to the 10×15s retry queue), so lifecycle + heartbeat can't stack duplicate terminates. |
| **§8.4 Retry exhaustion surfaced** | Orchestrator shows a system warning + dismissible amber banner (auto-dismiss 30s) when the server was never confirmed ended. |
| **§7 Health-check non-gating** | Orchestrator fullscreen health check is fire-and-forget (3s timeout) — a hung platform call can't freeze T-0/T-1/auto-close/safety-net. |
| **§8.11 Summary never hangs** | Isar persistence wrapped in a 5s timeout; the countdown into Idle always starts. |

Still deferred (out of core-flow scope): §3 WS reconnect backoff, §5 crash/startup watchdog, §6 popup hygiene, §8.5–8.8, §8.10, §8.12.