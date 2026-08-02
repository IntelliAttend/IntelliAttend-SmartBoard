# Release Notebook — validation-candidate-v2

> The permanent audit trail for the Phase 2 Validation Candidate.
> **This is NOT a production-ready release.** It is the frozen implementation
> entering controlled Phase 2 hardware validation.
> Tag: `validation-candidate-v2` (never moved, deleted, or reused).

## Identity

| Field | Value |
|-------|-------|
| Tag | `validation-candidate-v2` |
| Build | v5.5.0+22 (release `v5.5.0.22`, 2026-08-02) |
| Branch | `school-main` |
| Product-code commit | `82d43d9` |
| Date | 2026-08-01 (tag) / 2026-08-02 (release) |
| CI Validation | **PASS** (179 tests on windows-latest; GATE 75/75 executed) |
| Authenticode | All 3 binaries signed `CN=IntelliAttend SmartBoard` and chained to signing root (offline verify, run 30730843811 step 22) |
| Hardware Validation | Pending (Gates A–F) |
| Fleet Validation | Pending (SC-110…SC-115) |
| Release Readiness Review | Pending (Dev / QA / Ops / Product sign-off) |

> Note: commits `82d43d9..24af384` post-date the tag and are workflow/version
> only (CI test job on windows-latest, bash-shell audits, Release-tag filter,
> offline Authenticode verification). Builds +19/+20/+21 were version bumps
> from cancelled Auto-Deploy runs that produced no artifacts; the canonical
> validated artifact is **v5.5.0.22**. The tagged tree is product-identical to
> the current `school-main` HEAD.

## Why v2 (relationship to v1)

| | `validation-candidate-v1` | `validation-candidate-v2` |
|---|---------------------------|---------------------------|
| Commit | `5e89dc0` | `82d43d9` |
| CI | RED (analyzer warnings) | GREEN (analyzer clean, 179 tests) |
| Product code | Phase 1 stabilization | Identical + 7 lint-only fixes (zero behavior change) |
| Hardware evidence | none | none |
| Status | Superseded — kept for history | **Current frozen candidate** |

## Rules from this point

- **Updater feature freeze:** bug fixes only. No features, no refactors, no
  "small improvements".
- Only defect fixes discovered during hardware testing may land on this line
  until the RRR completes.
- **Fleet deployment is gated:** Auto-Deploy builds + archives artifacts on
  every `lib/**` push, but the fleet `ci-upload` (force=true, rollout 100%) runs
  ONLY on a manual `workflow_dispatch` with `promote=true`. No fleet updates
  during Phase 2. (Verified: run 30730843811 archived artifacts and **skipped**
  the fleet upload.)
- **Release workflow triggers on version tags only** — candidate/audit tags
  never start a release build.

## Artifacts (audit trail)

- Phase 1 Validation Report — `docs/phase1_validation_report.md`
- Phase 1 Change Log — `docs/phase1_session_changelog.md`
- Machine-generated evidence — `build/validation/Phase1ValidationReport.{md,json}`
- Phase 2 Hardware Validation Plan (v1.1, frozen) — `docs/phase2_hardware_validation_plan.md`
- Build artifacts per release: GitHub Release assets + Actions artifact
  `validation-candidate-<version>` (setup.exe, update_agent.exe, symbols,
  SHA256SUMS, build-info.json)
- Release Readiness Review — `docs/release/validation-candidate-v2/rrr_checklist.md` (to be completed)
- Hardware test evidence — (to be added by HW Lab, Gates A–F)
- Pilot deployment results — (to be added by Fleet Ops, SC-110…SC-115)
- Final production sign-off — (to be added at RRR)

## Branch strategy

```text
validation-candidate-v2 (tag)
        │
        ▼
Hardware Validation Branch
        │
        ├── Only bug fixes from hardware findings
        │
        ▼
validation-candidate-v3 (if needed)
        │
        ▼
Pilot Deployment (promote=true)
        │
        ▼
release-v5.5.0
```

Do not add unrelated improvements or feature work to this line until the
updater is production-qualified.
