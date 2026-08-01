# Phase 2 — Hardware & Operational Validation Plan

**Status:** APPROVED — pending execution
**Predecessor:** Phase 1 CI Validation — **GATE PASS** (75/75 executed, 0 failed, 40 pending)
**Decision (reviewer, 2026-08-01):**
- ✅ Phase 1 code approved for merge into `school-main`
- ✅ Release **tagged "Validation Candidate"** (NOT "Production Ready")
- ✅ Updater **feature freeze** in effect while hardware validation runs
- ❌ No fleet-wide deployment until all 40 pending scenarios are executed with evidence

This document turns the 40 PENDING scenarios from
`build/validation/Phase1ValidationReport.json` into executable test plans.

---

## 1. Charter & Operating Rules

**Mission:** prove the 40 hardware/fleet scenarios in the Phase 1 gap matrix with
real, documented evidence — or fail them loudly.

**Feature freeze (updater subsystem only):**
- ✅ Allowed: bug fixes, evidence logging, test instrumentation
- ❌ Forbidden: new features, refactors, architecture changes, "small improvements"
- Rationale: every code change resets confidence; the codebase under test must
  remain identical across the entire campaign (record the exact commit per run).

**Version under test:** the merge commit, tagged `validation-candidate-v1`
(Phase 1 final: v5.5.0+17 `fb27994` + Phase 1 fixes).

---

## 2. Lab Topology

### 2.1 Hardware Lab (4 machines + 1 switch)

| Machine | Role | Purpose | Never used for |
|---------|------|---------|----------------|
| **A — Golden Reference** | Known-good baseline | Golden image, recovery reference, `Known Good → Update → Verify` loops | Chaos injection |
| **B — Developer Validation** | Daily regression | Normal updates, smoke, rebuild verification | Non-idealized hardware |
| **C — Chaos (Destruction) Machine** | Break everything | Power cuts, kills, corruption, disk-full, network drop | Evidence of "known good" |
| **D — Soak Machine** | Long-run stability | 500+ update/rollback/restart cycles over days | Fast-cycle decisions |

Supporting equipment:
- Programmable PDU / smart power strip (per-port cut, scriptable) for Gate A.
- Two identical images (v5.5.0 and v5.6.0) pre-built and checksummed.
- Screenshot + video capture on every machine; serial/log capture if available.

### 2.2 Pilot Fleet (staged)

Deploy ring starting at 1 board, expanding only on observed stability (Gate F).

---

## 3. Gate Campaigns

Gate order is **fixed**: A → B → C → D → E → F. A gate is only "closed" when all
its scenarios have evidence and a verdict. The gate closes **green** or **red**
(no partial closes).

### Gate A — Power Failure Campaign  (SC-051 → SC-065)

**Machine:** C. **Scenario count:** 15.

Inject a **hard power cut** at every pipeline stage via the PDU. For the
installer-copy stages, additionally inject at ~50% and ~95%.

| SC | Stage of power loss |
|----|---------------------|
| SC-051 | after manifest received, before download |
| SC-052 | during download start |
| SC-053 | during download at 20% |
| SC-054 | during download at 40% |
| SC-055 | during download at 80% |
| SC-056 | during download at 99% |
| SC-057 | after download (during hash verify) |
| SC-058 | during backup creation |
| SC-059 | during installer launch |
| SC-060 | during installer copy at 50% |
| SC-061 | during installer copy at 95% |
| SC-062 | before app restart |
| SC-063 | after app restart |
| SC-064 | during post-install cleanup |
| SC-065 | after post-install cleanup |

**Procedure per scenario:**
1. Restore **Machine C** to known-good from Machine A image; verify boot.
2. Trigger the update so it reaches the target stage (monitor `update_state.json`
   / logs to confirm stage).
3. Cut PDU power. Wait 10 s. Restore power.
4. Boot; record which version boots and its health/rollback state.
5. Assert: **machine boots old OR new version — never a broken state.**
6. If new version boots: run 3 stable boots before declaring clean.

**Pass criteria:** 0 bricked boards; 0 unbootable states; every scenario has
video + `update_state.json` + health log + boot log.

---

### Gate B — Recovery Campaign  (SC-066, SC-067, SC-070, SC-071, SC-041, SC-042, SC-050, SC-086, SC-087)

**Machine:** C. **Scenario count:** 9.

Inject process-level and integrity failures and verify **automatic recovery**.

| SC | Failure injected | Expected recovery |
|----|------------------|-------------------|
| SC-066 | `shutdown /r /t 0` during download stages | Boots old or new; never broken |
| SC-067 | `shutdown /r /t 0` during install | Boots old or new; never broken |
| SC-070 | kill `update_agent.exe` mid-install | State file consistent; next boot recovers |
| SC-071 | kill installer process externally | No partial install; old version intact |
| SC-041 | installer hangs / times out | Timeout path fires; no wedge; recoverable |
| SC-042 | installer exit codes 0/1/5/3010 | 0/3010 treated success; 1/5 handled & reported |
| SC-050 | old-version / unsigned agent offered | Rejected before install; hash/signature checked |
| SC-086 | tampered rollback backup at restore | Detect tamper; refuse restore; never restore corrupt |
| SC-087 | wrong/missing code-sign cert on installer | Install blocked; error surfaced |

**Pass criteria:** every scenario recovers automatically or fails loudly with a
documented, user-actionable error. No silent corruption.

---

### Gate C — Persistence & Integrity Campaign  (SC-038, SC-039, SC-074, SC-075 + data matrix)

**Machine:** B (data matrix) and C (ACL/locks).

**Scenario tests:**

| SC | Test | Method |
|----|------|--------|
| SC-038 | backup drive becomes unavailable mid-backup | detach volume during backup; verify abort + rollback still possible |
| SC-039 | backup dir read-only (ACL) at update time | revoke ACL; verify fail-closed abort, no silent loss |
| SC-074 | installer / agent / DLL locked during real install | hold file handles; verify clean failure |
| SC-075 | log file locked during agent run | hold handle on agent log; verify agent continues |

**Persistence matrix** (verify byte-identical before → after a failed AND a
successful update, on Machine B):

| Item | Path |
|------|------|
| Logs | `Data\Logs\*` |
| Certificates | `Data\certs\*` |
| Redis / WebSocket config | `Config\*` |
| Board ID / registration | `Data\registration.json` |
| Offline cache | `Cache\offline.bin` |
| Attendance cache | `Data\attendance_queue.json` |
| Settings / env | `Config\env.json`, `Config\config.json` |

**Pass criteria:** every item byte-identical after both a failed and a
successful update; ACL/backup failures abort the update without data loss.

---

### Gate D — Performance & Capacity Campaign  (SC-079, SC-080)

**Machine:** C (load) and B (baseline).

| SC | Load condition | Measured during download, verify, install, restart |
|----|----------------|-----------------------------------------------------|
| SC-079 | RAM at 95% / 99% | download/install completes; no OOM; handles stable |
| SC-080 | CPU at 100% | pipeline completes; no starvation; no watchdog false fire |

**Record for every run (baseline and loaded):**

```
download_time, install_time, restart_time, boot_time
memory_peak, cpu_peak, disk_used, handle_count, thread_count
```

**Pass criteria:** update completes under load within 2× the unloaded baseline;
no crash, no OOM, no wedge.

---

### Gate E — Soak Campaign  (SC-102, SC-107, SC-108, SC-109)

**Machine:** D (SC-102). **Fleet:** (SC-107…SC-109, see Gate F).

**SC-102 — 500 real update cycles on Machine D:**

```
update → verify → rollback → update → restart → (repeat)
```

- Not simulated: real installer runs, real restarts.
- Capture handle count / RSS / thread count at intervals; assert flat growth.
- **Acceptance:** 0 crashes, 0 leaks, 0 corruption across 500 cycles.

**SC-107/108/109 — kiosk running 7/14/30 days then an update arrives** (fleet):
- A board in normal classroom operation for the stated duration receives a real
  update; verify clean install + config/data preservation + health report.
- Executed on the pilot fleet in Gate F (interleaved with ramp).

---

### Gate F — Pilot Fleet Ramp  (SC-110 → SC-115)

**Owner:** Fleet Ops. **Method:** strictly staged, observe-at-each-ring.

| SC | Ring size | Hold before advancing |
|----|-----------|-----------------------|
| SC-110 | 1 board | 48 h, all healthy |
| SC-111 | 5 boards | 48 h, all healthy |
| SC-112 | 20 boards | 72 h, all healthy |
| SC-113 | 100 boards | 7 days, all healthy |
| SC-114 | 500 boards | 7 days, all healthy |
| SC-115 | 1000 boards | 14 days, all healthy |

Never jump a ring (e.g., 1 → 100). Each ring is a real release of the
validation-candidate build; rollback via Gate 5 drill if unhealthy.

**Pilot success =** 0 rollback failures, 0 corrupted installs, 0 bricked boards.

---

## 4. Evidence Standard

No `PASS` without evidence. Every scenario result must include all fields:

```
Scenario ID      # e.g. SC-057
Objective        # one-line intent
Machine          # A / B / C / D / board serial
Version (build)  # exact commit / tag
Timestamp        # ISO-8601 UTC
Expected         # from this plan / acceptance matrix
Observed         # what actually happened
Logs             # paths: update_state.json, agent log, installer log, health log
Video            # capture path (power/crash scenarios)
Verdict          # PASS / FAIL / BLOCKED (BLOCKED = no verdict possible)
Triage           # for FAIL: root cause, owner, fix, re-run result
```

Each gate produces a `Gate-<Letter>_report.md` in `build/validation/` following
the same structure as the Phase 1 report, and results are appended to the master
`build/validation/Phase2ValidationReport.json`.

---

## 5. Production Release Gates

A production release requires **all five** gates green.

| Gate | Criterion | Status now |
|------|-----------|------------|
| 1 — CI | Phase 1 harness green | ✅ COMPLETE |
| 2 — Hardware | Gates A–E closed with evidence | ❌ OPEN |
| 3 — Pilot | 0 rollback failures, 0 corrupted installs, 0 bricked | ❌ OPEN |
| 4 — Operations | Dashboard, telemetry, rollback metrics, version & health reporting, alerts verified | ❌ OPEN |
| 5 — Disaster Recovery Drill | Simulate "v5.6 has a critical bug": can every board be returned to v5.5 safely? Time-boxed. If uncertain → NOT production-ready | ❌ OPEN |

### Gate 5 — Disaster Recovery Drill (define now, execute before release)

1. Release v5.6.0 to the 1000-board ring.
2. Declare a critical v5.6.0 defect.
3. Pause updates (server-side switch), push a rollback manifest to v5.5.0.
4. Measure: boards reverted, time to revert, boards stuck.
5. **Acceptance:** 100% revert; revert time documented; zero manual intervention
   per board. Otherwise: not production-ready.

---

## 6. Release Readiness Review (RRR)

A release moves to production **only if all four roles approve**, each with the
stated evidence.

| Role | Responsibility | Required evidence |
|------|----------------|-------------------|
| Development | Code correctness | CI green, Phase 1 validation report, code review |
| QA / Validation | Hardware & fault testing | Hardware lab results, chaos tests (Gates A–E) |
| Operations | Deployment readiness | Rollback plan, monitoring/telemetry, runbooks (Gate 4–5) |
| Product / Stakeholder | Business approval | Pilot results, deployment plan (Gate F) |

Sign-off is recorded per release in the RRR checklist. A single **NO** holds the
release.

---

## 7. Roles & Owners

| Role | Responsibility |
|------|----------------|
| Hardware Lab lead | Machines A–D, Gates A–D execution |
| Chaos engineer | Machine C daily destruction runs |
| Soak engineer | Machine D, SC-102 |
| Fleet Ops | Gate F ramps, SC-107–109 |
| QA / Validation | Evidence standard, gate report authoring, RRR QA evidence |
| Dev (on-call) | Bug fixes only (freeze); triage of FAILs |

---

## 8. Definition of Done — Phase 2

- All 40 pending scenarios executed with the evidence standard above.
- Gate A–E closed (green or red-with-triage); Gate F pilot completed.
- Phase 2 report (`build/validation/Phase2ValidationReport.md`) written.
- RRR completed with all four sign-offs.
- Tag moves from `validation-candidate-v1` → production release candidate, or
  defects are triaged into a documented fix + re-validation loop.
