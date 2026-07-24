# Phase 1 — Update Agent Technical Specification

**Document version:** 3.0  
**Date:** July 22, 2026  
**Status:** Implementation complete — hardened  
**Classification:** Frozen contract — no implementation without approval

---

## 1. Purpose

This document defines the binding contract between the Flutter application and the detached update agent (`update_agent.exe`). Every state transition, failure mode, retry policy, and recovery path described here is deterministic — there are no "maybes" or "shoulds." Implementation must match this spec exactly.

The agent is a standalone ~150 KB C++ executable. It has no Flutter dependency, no external libraries, and uses only Win32 APIs.

---

## 2. Process Ownership

### 2.1 Operation Ownership

No ambiguity. Every operation has exactly one owner.

| Operation | Owner | Notes |
|-----------|-------|-------|
| Detect update available | **App** | Via `AutoUpdater` polling server |
| Download MSI | **App** | HTTP download with progress |
| Verify SHA-256 hash | **App** | Before agent launch |
| Verify Authenticode signature | **App** | Before agent launch |
| Write `update_state.json` | **App** | Creates file with state=`verified` |
| Launch `update_agent.exe` | **App** | `Process.start` with detached mode |
| Exit application | **App** | `exit(0)` after agent launch |
| Wait for app process exit | **Agent** | `WaitForSingleObject` on PID |
| Run `msiexec` | **Agent** | `CreateProcess` with /qn |
| Verify installed version | **Agent** | `GetFileVersionInfoW` |
| Restart application | **Agent** | `CreateProcess` with --autostart flag |
| Cleanup temp files | **Agent** | Delete MSI, old state |
| Write completion state | **Agent** | Write state=`completed` to JSON |

### 2.2 State File Ownership

| File | Owner | Agent touches? | App touches? |
|------|-------|----------------|--------------|
| `installation_state.json` | **App** | Never | Yes — lifecycle transitions |
| `installation_context.json` | **App** | Never | Yes — version, board ID, counts |
| `update_health.json` | **App** | Never | Yes — crash loop detection |
| `update_state.json` | **Transfers** | After app exit | Before agent launch |

### 2.3 Ownership Transfer Protocol

```
PHASE 1: App owns update_state.json
  App writes: state = "verified"
  App launches agent
  App calls exit(0)
  → App process terminates

PHASE 2: Nobody owns update_state.json
  Brief window (milliseconds) where no process writes

PHASE 3: Agent owns update_state.json
  Agent reads file (takes ownership)
  Agent writes: state = "installing"
  Agent writes: state = "installed"
  Agent writes: state = "completed"
  Agent calls exit(0)
  → Agent process terminates

PHASE 4: Nobody owns update_state.json
  Brief window until app relaunches

PHASE 5: App reclaims ownership
  App reads file (verifies completion)
  App deletes file
  → Clean state for next update
```

**Critical rule:** At most one process writes to `update_state.json` at any time. The transfer is mediated by process exit — there is no lock, no mutex, no IPC.

### 2.4 Inter-Process Communication

There is **zero IPC** between the app and agent. No pipes, no sockets, no shared memory. All communication is through the `update_state.json` file on disk. The agent reads it once on startup; the app writes it before exit.

---

## 3. State Machine

### 3.1 Agent States (8 states)

```
                          ┌──────────────────────────────────────────────┐
                          │                AGENT LIFECYCLE               │
                          │                                              │
                          │  ┌──────┐    ┌─────────┐    ┌───────────┐   │
                          │  │ BOOT │───▶│ READING │───▶│  WAITING  │   │
                          │  └──────┘    └─────────┘    │ APP EXIT  │   │
                          │                              └─────┬─────┘   │
                          │                                    │         │
                          │                                    ▼         │
                          │  ┌───────┐    ┌───────────┐   ┌─────────┐  │
                          │  │ CLEAN │◀───│RESTARTING │◀──│INSTALL  │  │
                          │  │  UP   │    └───────────┘   │  ING    │  │
                          │  └──┬────┘                     └─────────┘  │
                          │     │                                       │
                          │     ▼                                       │
                          │  ┌──────┐                                    │
                          │  │ DONE │                                    │
                          │  └──────┘                                    │
                          └──────────────────────────────────────────────┘
```

### 3.2 Normal Transitions

| # | From | To | Trigger | Guard | Timeout |
|---|------|----|---------|-------|---------|
| T1 | *(start)* | BOOT | Process entry | — | — |
| T2 | BOOT | READING | Parse `update_state.json` | File exists, readable | — |
| T3 | READING | WAITING_APP_EXIT | State field = `verified`, all required fields present | Schema valid, checksum valid | — |
| T4 | WAITING_APP_EXIT | INSTALLING | App PID no longer running | `WaitForSingleObject` returns | 60s |
| T5 | INSTALLING | VERIFYING | `msiexec` exits 0 or 3010 | Exit code checked | 300s |
| T6 | VERIFYING | RESTARTING | New exe exists + version matches target | `GetFileVersionInfoW` matches | — |
| T7 | RESTARTING | CLEANUP | New process started successfully | `CreateProcess` succeeds | 10s |
| T8 | CLEANUP | DONE | MSI deleted, state file updated | — | — |

### 3.3 Failure Transitions

| # | From | To | Trigger | Recovery Path | Exit Code |
|---|------|----|---------|---------------|-----------|
| F1 | BOOT | EXIT | No `update_state.json` or unreadable | App retries on next launch (§5.7) | 5 |
| F2 | BOOT | EXIT | Schema version > supported | App deletes stale state, retries | 5 |
| F3 | BOOT | EXIT | Checksum mismatch (corrupted) | App deletes stale state, retries | 5 |
| F4 | BOOT | EXIT | Required field missing or wrong type | App deletes stale state, retries | 5 |
| F5 | READING | EXIT | State ≠ `verified` | App detects on next launch, retries or recovers | 5 |
| F6 | WAITING_APP_EXIT | EXIT | App PID still running after 60s + TerminateProcess fails | App re-detects on next launch, retries agent | 1 |
| F7 | INSTALLING | INSTALLING | `msiexec` exits non-zero (retryable error) | Retry per §6.1 | — |
| F8 | INSTALLING | EXIT | All MSI retries exhausted | App reads state=`failed`, enters recovery | 2 |
| F9 | VERIFYING | EXIT | New exe not found after 10s poll | App reads state=`failed`, re-downloads | 3 |
| F10 | VERIFYING | EXIT | Version mismatch after exe found | App reads state=`failed`, re-downloads | 3 |
| F11 | RESTARTING | EXIT | `CreateProcess` fails (antivirus, permissions) | App reads state=`failed`, enters recovery | 4 |
| F12 | RESTARTING | EXIT | New process exits within 5s (crash on start) | App reads state=`failed`, enters recovery | 4 |
| F13 | ANY | EXIT | Agent total lifetime > 600s | Force exit, app detects on next launch | 0* |
| F14 | ANY | EXIT | State file write fails (disk full) | Agent logs to stderr, exits | 5 |

*Exit code 0 on lifetime timeout because the agent did its best; the app must resolve on next launch.

### 3.4 App-Side Recovery on Stale State

When the app launches and finds `update_state.json`:

```
State = "verified"      → Agent never launched or crashed at boot
  → Re-launch agent (state is still valid)

State = "installing"    → Agent crashed during MSI install
  → Check if msiexec still running → wait
  → Check exe version on disk → if correct, update succeeded
  → Otherwise → delete state, re-download, retry

State = "installed"     → Agent crashed before verification/restart
  → Check exe version → if correct, launch app manually
  → Otherwise → delete state, retry

State = "restarting"    → Agent crashed during restart
  → Check exe version → launch app manually

State = "installed"     → Agent succeeded, app just needs to clean up
  → Delete state file, continue normal startup

State = "failed"        → Agent reported failure
  → Read error message, log it, enter recovery mode
  → If retriable → re-download and retry
  → If not → show recovery screen
```

---

## 4. Communication Contract

### 4.1 update_state.json — Schema v1

```json
{
  "schema": 1,
  "owner": "app",
  "msi_path": "C:\\Users\\...\\Updates\\IASB-5.6.0.msi",
  "target_version": "5.6.0+12",
  "expected_sha256": "a1b2c3...",
  "app_pid": 12345,
  "app_exe_path": "C:\\Users\\...\\App\\intelliattend_smartboard.exe",
  "log_path": "C:\\Users\\...\\Logs\\update.log",
  "state": "verified",
  "error": null,
  "created_at": "2026-07-22T10:30:00.000Z",
  "completed_at": null,
  "attempt": 1,
  "checksum": "d4e5f6..."
}
```

### 4.2 Field Classification

| Field | Type | Mandatory | Classification | Writer | Mutable? |
|-------|------|-----------|---------------|--------|----------|
| `schema` | int | Yes | **Immutable** | App | No |
| `owner` | string | Yes | **Mutable** | App→Agent | On ownership transfer |
| `msi_path` | string | Yes | **Immutable** | App | No |
| `target_version` | string | Yes | **Immutable** | App | No |
| `expected_sha256` | string | Yes | **Immutable** | App | No |
| `app_pid` | int | Yes | **Immutable** | App | No |
| `app_exe_path` | string | Yes | **Immutable** | App | No |
| `log_path` | string | Yes | **Immutable** | App | No |
| `state` | string | Yes | **Mutable** | Both | On every transition |
| `error` | string | No | **Mutable** | Agent | On failure only |
| `created_at` | string | Yes | **Immutable** | App | No |
| `completed_at` | string | No | **Mutable** | Agent | On completion only |
| `attempt` | int | Yes | **Mutable** | Agent | Incremented on retry |
| `checksum` | string | Yes | **Mutable** | Both | Recomputed on every write |

**Rules:**
- Immutable fields are set by the app and never modified by the agent
- Mutable fields are updated by the agent during its lifecycle
- The `checksum` covers all other fields (including mutable ones)
- The `owner` field transitions from `"app"` to `"agent"` when the agent reads the file

### 4.3 Checksum Algorithm

```
1. Build JSON object with all fields EXCEPT "checksum"
2. Encode as compact JSON (no whitespace)
3. Compute SHA-256 of UTF-8 bytes
4. Store hex digest as "checksum" field

Verification:
1. Read file
2. Remove "checksum" field from parsed JSON
3. Re-encode as compact JSON
4. Compute SHA-256
5. Compare with stored checksum
6. If mismatch → file is corrupt, treat as stale
```

### 4.4 App Writes (Before Agent Launch)

The app writes the complete file once with:

```json
{
  "schema": 1,
  "owner": "app",
  "msi_path": "...",
  "target_version": "...",
  "expected_sha256": "...",
  "app_pid": <current PID>,
  "app_exe_path": "...",
  "log_path": "...",
  "state": "verified",
  "error": null,
  "created_at": "<now ISO-8601>",
  "completed_at": null,
  "attempt": 1,
  "checksum": "<computed>"
}
```

### 4.5 Agent Writes (State Transitions)

Each agent write updates only the mutable fields and recomputes the checksum:

```
WAITING → INSTALLING:
  { state: "installing", owner: "agent", attempt: N+1, checksum: "..." }

INSTALLING → VERIFYING:
  { state: "installed", checksum: "..." }

VERIFYING → RESTARTING:
  { state: "restarting", checksum: "..." }

RESTARTING → DONE:
  { state: "installed", completed_at: "<now>", checksum: "..." }

ANY → FAILURE:
  { state: "failed", error: "<message>", completed_at: "<now>", checksum: "..." }
```

---

## 5. Failure Matrix

Every failure has one deterministic recovery path. No ambiguity.

| # | Failure | Detection | Recovery | Owner |
|---|---------|-----------|----------|-------|
| **Download failures** | | | | |
| F-01 | Network disconnect during download | HTTP read error | Resume from byte offset (HTTP Range) | App |
| F-02 | Server returns 404/500 | HTTP status code | Abort download, retry after backoff (§6.2) | App |
| F-03 | Disk full during download | Write exception | Abort, show error, enter recovery | App |
| F-04 | Partial download on crash | File size < expected | Delete partial file, re-download | App |
| **Verification failures** | | | | |
| F-05 | SHA-256 mismatch | Hash comparison | Delete MSI, re-download (§6.2) | App |
| F-06 | Authenticode signature invalid | `WinVerifyTrust` | Delete MSI, do not retry, show security error | App |
| F-07 | MSI file is corrupt/not MSI | `MsiOpenPackage` or magic bytes | Delete MSI, re-download | App |
| **State file failures** | | | | |
| F-08 | update_state.json missing at agent boot | `FileExists` | Agent exits code 5; app retries agent | Agent |
| F-09 | update_state.json corrupt (checksum mismatch) | Checksum verify | Agent exits code 5; app deletes + retries | Agent |
| F-10 | update_state.json write fails (disk full) | `WriteFile` error | Agent logs to stderr, exits code 5 | Agent |
| F-11 | State = "installing" at app launch (stale) | Read state file | Check exe version; if correct → success; else → retry | App |
| **Agent failures** | | | | |
| F-12 | Agent crashes during WAITING_APP_EXIT | PID check on next app launch | State still "verified"; re-launch agent | App |
| F-13 | Agent crashes during INSTALLING | PID check on next app launch | Check msiexec, check exe version, retry or recover | App |
| F-14 | Agent crashes during VERIFYING | PID check on next app launch | Check exe version; if correct → launch manually | App |
| F-15 | Agent crashes during RESTARTING | PID check on next app launch | Check exe version; if correct → launch manually | App |
| F-16 | Agent total lifetime > 600s | Internal timer | Force exit; app resolves on next launch | Agent |
| **MSI failures** | | | | |
| F-17 | msiexec exit 1603 (fatal error) | Exit code check | Retry per §6.1 (retryable) | Agent |
| F-18 | msiexec exit 1618 (another install in progress) | Exit code check | Retry per §6.1 (retryable) | Agent |
| F-19 | msiexec exit 1602 (user cancelled) | Exit code check | Not retryable; exit code 2 | Agent |
| F-20 | msiexec exit 3010 (reboot required) | Exit code check | Treat as success; restart app | Agent |
| F-21 | msiexec exit other non-zero | Exit code check | Retry per §6.1 (retryable) | Agent |
| F-22 | msiexec never exits (hung) | 300s timeout | Kill msiexec, retry | Agent |
| **Post-install failures** | | | | |
| F-23 | New exe not found after MSI exit | `FileExists` poll 10s | Retry once; if still missing → exit code 3 | Agent |
| F-24 | New exe version mismatch | `GetFileVersionInfoW` | Exit code 3; app re-downloads | Agent |
| F-25 | New exe crashes on first launch | Process exits < 5s | Agent exit code 4; app enters recovery | Agent |
| **Process failures** | | | | |
| F-26 | App PID still running after 60s wait | `WaitForSingleObject` timeout | `TerminateProcess` (force); if fails → exit code 1 | Agent |
| F-27 | Agent can't launch msiexec (permissions) | `CreateProcess` error | Exit code 2; app enters recovery | Agent |
| F-28 | Agent can't launch new app (antivirus) | `CreateProcess` error | Exit code 4; app shows manual restart instructions | Agent |
| **System failures** | | | | |
| F-29 | Power loss during MSI install | N/A (Windows Installer handles) | On reboot: check exe version; if correct → success; else → retry | App |
| F-30 | Reboot during MSI install | Pending reboot detection | Windows Installer completes on reboot; app resolves on next boot | App |
| F-31 | Antivirus locks MSI file | `DeleteFile` error in cleanup | Log warning; non-fatal; state is already "completed" | Agent |
| F-32 | Registry locked by another process | MSI install fails | Retry per §6.1 | Agent |

---

## 6. Retry Policy

### 6.1 MSI Install Retry (Agent-Side)

Fixed retry with linear backoff. Maximum 3 attempts total.

```
Attempt 1:  msiexec → fails
            Wait 5 seconds
Attempt 2:  msiexec → fails
            Wait 10 seconds
Attempt 3:  msiexec → fails
            Give up. Write state="failed", exit(2)
```

**Retryable exit codes:** 1603, 1618, 1619, and any other non-zero code except 1602 (user cancelled) and 1604 (install suspended).

**Non-retryable exit codes:** 1602, 1604, 5 (access denied).

### 6.2 Download Retry (App-Side)

Exponential backoff. Maximum 5 attempts.

```
Attempt 1:  Download → fails
            Wait 2 seconds
Attempt 2:  Download → fails
            Wait 5 seconds
Attempt 3:  Download → fails
            Wait 15 seconds
Attempt 4:  Download → fails
            Wait 60 seconds
Attempt 5:  Download → fails
            Give up. Show error screen.
```

**Resume policy:** If the server supports HTTP Range headers, resume from the last byte received. If not, restart from byte 0.

### 6.3 Agent Re-Launch Retry (App-Side)

If the agent crashes before completing, the app retries once.

```
First launch:   Agent crashes → app detects stale state
App recovery:   If state = "verified" → re-launch agent once
                If re-launch also fails → enter recovery mode, show UI
```

---

## 7. Timeouts

| Operation | Timeout | Graceful Action | Force Action |
|-----------|---------|-----------------|--------------|
| Wait for app exit | 60 seconds | — | `TerminateProcess(appHandle)` |
| `TerminateProcess` wait | 5 seconds | — | Proceed anyway (exit code 1) |
| MSI install | 300 seconds (5 min) | Kill msiexec, retry | Exit code 2 |
| Post-install exe poll | 10 seconds | Poll every 500ms | Exit code 3 |
| Launch new app | Immediate | `CreateProcess` | Exit code 4 |
| Verify new app started | 5 seconds | `WaitForSingleObject` | Exit code 4 |
| Cleanup (delete MSI) | 5 seconds | `DeleteFileW` | Log warning, proceed |
| Agent total lifetime | 600 seconds (10 min) | — | `TerminateProcess(self)`, exit 0 |

---

## 8. Logging

### 8.1 Log Format

Every line follows this exact format:

```
[<ISO-8601-UTC>] [<LEVEL>]  <STATE>: <message>
```

- **Timestamp:** `YYYY-MM-DDTHH:MM:SS.sssZ` (millisecond precision, UTC)
- **Level:** `INFO`, `WARN`, `ERROR`
- **State:** Current agent state (BOOT, READING, WAITING, INSTALLING, VERIFYING, RESTARTING, CLEANUP, DONE)
- **Message:** Human-readable description

### 8.2 Required Log Events

The following events MUST appear in every successful update:

```
[2026-07-22T10:30:01.000Z] [INFO]  BOOT: update_agent.exe v1.0 starting, PID=9876
[2026-07-22T10:30:01.001Z] [INFO]  READING: Parsing update_state.json
[2026-07-22T10:30:01.002Z] [INFO]  READING: Schema v1, state=verified, target=5.6.0+12
[2026-07-22T10:30:01.003Z] [INFO]  READING: Checksum valid
[2026-07-22T10:30:01.004Z] [INFO]  READING: MSI verified at C:\...\IASB-5.6.0.msi
[2026-07-22T10:30:01.005Z] [INFO]  WAITING: Watching app PID=12345
[2026-07-22T10:30:05.000Z] [INFO]  WAITING: App PID 12345 exited (exit code 0)
[2026-07-22T10:30:05.001Z] [INFO]  INSTALLING: Attempt 1/3, msiexec /i "C:\...\IASB-5.6.0.msi" /qn /norestart /log "C:\...\msi_install.log"
[2026-07-22T10:30:45.000Z] [INFO]  INSTALLING: msiexec exited with code 0
[2026-07-22T10:30:45.001Z] [INFO]  VERIFYING: Checking C:\...\intelliattend_smartboard.exe
[2026-07-22T10:30:45.500Z] [INFO]  VERIFYING: Version 5.6.0+12 matches target
[2026-07-22T10:30:45.501Z] [INFO]  RESTARTING: Launching C:\...\intelliattend_smartboard.exe --intelliattend-autostart
[2026-07-22T10:30:46.000Z] [INFO]  RESTARTING: New process started, PID=54321
[2026-07-22T10:30:46.001Z] [INFO]  CLEANUP: Deleting MSI and state file
[2026-07-22T10:30:46.100Z] [INFO]  DONE: Update complete in 45.1s, exiting
```

### 8.3 Required Error Logs

On failure, the agent MUST log:

```
[<timestamp>] [ERROR] <STATE>: <failure description>
[<timestamp>] [ERROR] <STATE>: Exit code <N>, writing state=failed
[<timestamp>] [ERROR] <STATE>: <error detail from Win32 or msiexec>
```

Example:

```
[2026-07-22T10:30:45.000Z] [ERROR] INSTALLING: msiexec exited with code 1603
[2026-07-22T10:30:45.001Z] [WARN]  INSTALLING: Retry 2/3 in 10 seconds
[2026-07-22T10:30:55.000Z] [INFO]  INSTALLING: Attempt 2/3
[2026-07-22T10:31:35.000Z] [ERROR] INSTALLING: msiexec exited with code 1603
[2026-07-22T10:31:35.001Z] [WARN]  INSTALLING: Retry 3/3 in 10 seconds
[2026-07-22T10:31:45.000Z] [INFO]  INSTALLING: Attempt 3/3
[2026-07-22T10:32:25.000Z] [ERROR] INSTALLING: msiexec exited with code 1603
[2026-07-22T10:32:25.001Z] [ERROR] INSTALLING: All retries exhausted
[2026-07-22T10:32:25.002Z] [ERROR] INSTALLING: Writing state=failed, exit code 2
```

### 8.4 Log File Policy

- **Location:** Path specified in `update_state.json.log_path`
- **Max size:** 512 KB (truncate oldest lines if exceeded)
- **Encoding:** UTF-8
- **Line endings:** `\r\n` (Windows standard)
- **Retention:** Kept until next successful update (cleaned up by app, not agent)

---

## 9. Security

### 9.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Another process replaces `update_state.json` | **Mitigated by checksum.** Agent verifies SHA-256 on read. Corrupt/tampered file → agent exits code 5. |
| Another process replaces the MSI after verification | **Mitigated by file locking.** App opens MSI with `FILE_SHARE_READ` only during verification. Agent re-verifies SHA-256 before `msiexec`. |
| Tampered agent binary | **Not in scope** for this phase. Agent is deployed alongside MSI via same signed installer. Future: Authenticode verify agent itself. |
| Agent runs with elevated privileges | **Prohibited.** Agent must not request elevation. MSI installer handles UAC if needed. |
| Agent makes network requests | **Prohibited.** Agent has no network code. No WinHTTP, no WinINet, no socket calls. |
| Agent modifies registry | **Prohibited.** Only `msiexec` modifies registry, and only through the MSI. |
| Agent persists across reboots | **Prohibited.** No auto-start, no scheduled tasks, no services. Agent is fire-and-forget. |
| Race condition on `update_state.json` | **Mitigated by ownership model.** Only one process writes at any time. Transfer is mediated by process exit. |
| MSI contains malware | **Mitigated by Authenticode.** App verifies `WinVerifyTrust` before agent launch. Agent does not re-verify (trust boundary at app exit). |
| Antivirus quarantines agent | **Detected at launch.** If `CreateProcess` for agent fails, app enters recovery mode and shows manual recovery instructions. |

### 9.2 File Permissions

| File | Created With | Permissions |
|------|-------------|-------------|
| `update_state.json` | App | Creator-full, others-read (standard user ACL) |
| `update_agent.exe` | MSI installer | Inherited from `App\` directory |
| MSI download | App | Creator-full, others-read |
| Agent log file | Agent | Creator-full, others-read |

### 9.3 Integrity Verification Chain

```
Server → App:    HTTPS + certificate pinning
App → MSI:       SHA-256 hash comparison
App → MSI:       Authenticode signature (WinVerifyTrust)
App → State:     SHA-256 checksum of JSON payload
Agent → State:   SHA-256 checksum of JSON payload (re-verify)
Agent → MSI:     SHA-256 re-verify before msiexec (defense in depth)
Agent → Version: GetFileVersionInfoW after install
```

---

## 10. Exit Codes

| Code | Meaning | App Action |
|------|---------|------------|
| 0 | Success — update completed, app relaunched | Delete state, continue |
| 0* | Lifetime timeout (600s) — agent did its best | Check exe version, resolve |
| 1 | App exit timeout — couldn't wait for app | Retry agent on next launch |
| 2 | MSI install failed — all retries exhausted | Re-download or recovery |
| 3 | Post-install verification failed | Re-download or recovery |
| 4 | App restart failed | Show manual restart instructions |
| 5 | Invalid state file | Delete state, re-download |

---

## 11. Telemetry Events

Lifecycle events for operational visibility. These are aggregated server-side — no personal data.

### 11.1 Event Types

| Event | Trigger | Payload |
|-------|---------|---------|
| `update.started` | App begins update pipeline | `{ current_version, target_version }` |
| `update.download_completed` | MSI download finished | `{ bytes, duration_ms }` |
| `update.download_resumed` | Download resumed from offset | `{ resume_byte, total_bytes }` |
| `update.verified` | SHA-256 + Authenticode passed | `{ file_size }` |
| `update.agent_launched` | Agent process started | `{ agent_pid, app_pid }` |
| `update.agent_exited` | Agent process terminated | `{ exit_code, duration_ms }` |
| `update.install_started` | msiexec launched | `{ attempt, msi_size }` |
| `update.install_completed` | msiexec exited successfully | `{ exit_code, duration_ms }` |
| `update.install_retried` | msiexec failed, retrying | `{ attempt, exit_code }` |
| `update.install_failed` | All retries exhausted | `{ attempts, last_exit_code }` |
| `update.version_verified` | Post-install version check passed | `{ installed_version }` |
| `update.version_mismatch` | Post-install version check failed | `{ expected, actual }` |
| `update.app_restarted` | New process launched | `{ new_pid }` |
| `update.rollback_triggered` | Rollback to previous version | `{ from_version, to_version, reason }` |
| `update.recovery_entered` | App entered recovery mode | `{ state_at_discovery, error }` |
| `update.completed` | Full pipeline success | `{ from_version, to_version, total_duration_ms }` |

### 11.2 Reporting

Events are batched and sent to the server's telemetry endpoint on the next heartbeat. If the network is unavailable, events are stored locally (max 100 events, FIFO) and sent on next successful heartbeat.

### 11.3 Usage

These events answer:
- What percentage of boards successfully update to each release?
- Which release versions cause the most rollbacks?
- Is the agent timing out more frequently on certain hardware?
- Are Authenticode failures clustered in specific network environments?
- What is the median update duration across the fleet?

---

## 12. Testing Matrix

### 12.1 Happy Path

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-01 | Normal update | Clean network, admin rights | Update completes in < 60s |
| T-02 | Update with reboot required | MSI returns 3010 | Agent restarts app, notifies user of pending reboot |
| T-03 | Silent update (auto-start) | Board in kiosk mode | Update applies, app restarts with --autostart |

### 12.2 Agent Crash Scenarios

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-04 | Kill agent before MSI start | Task Manager kill | App detects stale state, retries agent |
| T-05 | Kill agent during MSI | Kill during install | App checks exe version, retries or recovers |
| T-06 | Kill agent during restart | Kill after MSI success | App launches manually on next boot |
| T-07 | Kill agent 3 times in a row | Simulate repeated crashes | App enters recovery mode, shows UI |

### 12.3 MSI Failure Scenarios

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-08 | MSI exit 1603 | Corrupt MSI or permission issue | Retry 3x, then fail |
| T-09 | MSI exit 1618 | Another MSI running | Retry 3x, then fail |
| T-10 | MSI exit 1602 | User cancellation (shouldn't happen in silent) | Fail immediately, no retry |
| T-11 | MSI hangs | MSI never exits | Kill after 300s, retry |
| T-12 | MSI partial install + power loss | Kill power during install | Windows Installer rolls back; app retries |

### 12.4 Verification Failure Scenarios

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-13 | SHA-256 mismatch | Corrupt MSI | Delete, re-download |
| T-14 | Authenticode invalid | Unsigned or modified MSI | Delete, show security error |
| T-15 | Version mismatch after install | Wrong MSI version | Exit code 3, app re-downloads |
| T-16 | Exe not found after install | MSI succeeded but exe missing | Exit code 3, app re-downloads |

### 12.5 System Failure Scenarios

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-17 | Disk full | < 100MB free | Agent detects write failure, exits code 5 |
| T-18 | Antivirus locks MSI | AV scanning MSI | Retry, log warning, eventual success |
| T-19 | Read-only Data directory | Permission issue | App detects at startup, recovery mode |
| T-20 | Corrupt state file | Manual hex edit | Checksum mismatch, agent exits code 5 |
| T-21 | Missing state file | File deleted between launch | Agent exits code 5, app retries |
| T-22 | Pending reboot | Windows Update rebooted | MSI completes on boot, app resolves |
| T-23 | App killed via Task Manager | User force-kills app | Agent detects PID exit, proceeds normally |
| T-24 | Agent launched but app not exiting | App hangs | Agent waits 60s, TerminateProcess, proceed |

### 12.6 Security Scenarios

| # | Scenario | Preconditions | Expected Result |
|---|----------|--------------|-----------------|
| T-25 | Tampered state file (checksum) | Manual edit | Checksum mismatch, agent exits code 5 |
| T-26 | Tampered MSI | Modified binary | Authenticode fails, app rejects |
| T-27 | Agent run as admin | UAC prompt | Agent must not request elevation |
| T-28 | Two agents running | Race condition | Second agent detects file lock, exits |

---

## 13. Hardening (Implemented)

### 13.1 Singleton Mutex

The agent acquires a named mutex `Global\IntelliAttend.UpdateAgent` at boot. If another agent instance already holds the mutex, the new instance exits immediately. This prevents race conditions from concurrent updates.

**Implementation:** `singleton.h` — RAII `SingletonGuard` class.

### 13.2 Heartbeat Watchdog

During the INSTALLING state, the agent writes a heartbeat file (`agent_heartbeat.txt`) every few seconds. If the heartbeat stops updating, the app knows the agent is hung. The heartbeat file is deleted on successful completion.

**Implementation:** `heartbeat.h/cpp` — `Heartbeat::Init()`, `Pulse()`, `Stop()`.

### 13.3 Authenticode Verification (Defense in Depth)

Both the app and the agent independently verify the MSI's Authenticode signature. The agent also verifies the installed exe after installation. This ensures that even if the app's check is bypassed, the agent catches tampered binaries.

**Implementation:** `authenticode.h/cpp` — `VerifyAuthenticode()` using `WinVerifyTrust`.

### 13.4 Windows Restart Manager Integration

Before waiting for the app to exit, the agent uses the Restart Manager API to:
1. Identify processes locking files in the install directory
2. Request graceful shutdown via `RmShutdown`
3. Fall back to `WaitForSingleObject` + `TerminateProcess` if graceful shutdown fails

**Implementation:** `restart_manager.h/cpp` — `RestartManager::BeginSession()`, `GetLockedProcesses()`, `ShutdownApplications()`.

### 13.5 Install Journal

An append-only `install.journal` file records every step of the update process with timestamps. If power dies mid-install, the journal tells support exactly where it stopped. Each entry is pipe-delimited: `timestamp|OK/FAIL|step|detail`.

**Implementation:** `install_journal.h/cpp` — `InstallJournal::Record()`, `Read()`, `Clear()`.

### 13.6 Session Awareness

The agent checks `WTSGetActiveConsoleSessionId()` at boot. If no console session is active (e.g., user logged off), the agent logs a warning but continues — kiosk boards often run without a logged-in user.

**Implementation:** `session.h/cpp` — `IsConsoleSessionActive()`, `GetActiveSessionId()`.

### 13.7 Windows Event Log Integration

The agent writes structured events to the Windows Event Log under the "IntelliAttend Update" source. Enterprise IT can monitor update status via Event Viewer without accessing log files.

**Events:** `agent_start`, `install_complete`, `install_failed`, `verify_failed`, `restart_failed`, `agent_complete`.

**Implementation:** `event_log.h/cpp` — `EventLog::Register()`, `Info()`, `Warn()`, `Error()`.

---

## 14. Implementation Checklist

### Agent (C++ — `windows/update_agent/`)
- [x] `CMakeLists.txt` — standalone build, no Flutter dependency
- [x] `main.cpp` — entry point, state machine driver
- [x] `process_watcher.cpp` — `WaitForSingleObject` on app PID
- [x] `installer.cpp` — `CreateProcess` msiexec with arguments
- [x] `version_checker.cpp` — `GetFileVersionInfoW` verification
- [x] `launcher.cpp` — `CreateProcess` to restart app
- [x] `json_reader.cpp` — minimal JSON parser (no external deps)
- [x] `logger.cpp` — structured log writes with timestamp
- [x] `file_utils.cpp` — existence, size, hash, rename checks
- [x] `checksum.cpp` — SHA-256 verification (WinCrypt API)
- [x] `singleton.h` — named mutex, single instance guard
- [x] `heartbeat.h/cpp` — watchdog heartbeat file
- [x] `install_journal.h/cpp` — append-only transaction journal
- [x] `authenticode.h/cpp` — WinVerifyTrust signature verification
- [x] `restart_manager.h/cpp` — Windows Restart Manager integration
- [x] `session.h/cpp` — console session awareness
- [x] `event_log.h/cpp` — Windows Event Log integration
- [x] `resources/update_agent.rc` — VERSIONINFO resource

### Flutter Side
- [x] `lib/services/update_agent_launcher.dart` — write state, launch agent, exit
- [x] `lib/services/auto_updater.dart` — remove `_installMsi`, `_exitApp`
- [x] `lib/main.dart` — startup recovery for stale update state
- [x] `lib/core/state/state_persister.dart` — ownership-aware reads

### Testing
- [ ] All 28 test scenarios from §12 verified
- [ ] Log output reviewed for completeness
- [ ] Telemetry events verified in staging
- [ ] Stress tests per reviewer checklist
- [ ] C++ build verified with CMake
