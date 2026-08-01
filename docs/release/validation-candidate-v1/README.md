# Release Notebook — validation-candidate-v1

> **SUPERSEDED by `validation-candidate-v2`** (2026-08-01) — see
> `docs/release/validation-candidate-v2/README.md`. v1 had RED CI (analyzer
> warnings, zero hardware evidence); v2 carries identical product code plus
> 7 lint-only fixes and green CI. This notebook is kept as the historical
> record of the first candidate.

> The permanent audit trail for the Phase 1 Validation Candidate.
> **This is NOT a production-ready release.** It is the frozen implementation
> entering controlled Phase 2 hardware validation.
> Tag: `validation-candidate-v1` (never moved, deleted, or reused).

## Identity

| Field | Value |
|-------|-------|
| Tag | `validation-candidate-v1` |
| Build | v5.5.0+17 |
| Branch | `school-main` |
| Date | 2026-08-01 |
| CI Validation | **PASS** (75/75 executed, 115 total, 40 pending) |
| Hardware Validation | Pending (Gates A–F) |
| Fleet Validation | Pending (SC-110…SC-115) |
| Release Readiness Review | Pending (Dev / QA / Ops / Product sign-off) |

## Rules from this point

- **Updater feature freeze:** bug fixes only. No features, no refactors, no
  "small improvements".
- Only defect fixes discovered during hardware testing may land on this line
  until the RRR completes.
- Every change must strengthen confidence in the updater, never expand scope.

## Artifacts (audit trail)

- Architecture Audit — `docs/ARCHITECTURE.md`, `docs/OTA_UPDATE_SYSTEM.md`
- Phase 1 Validation Report — `docs/phase1_validation_report.md`
- Phase 1 Change Log — `docs/phase1_session_changelog.md`
- Machine-generated evidence — `build/validation/Phase1ValidationReport.{md,json}`
- Phase 2 Hardware Validation Plan — `docs/phase2_hardware_validation_plan.md`
- Release Readiness Review — `docs/release/validation-candidate-v1/rrr_checklist.md` (to be completed)
- Hardware test evidence — (to be added by HW Lab, Gates A–F)
- Pilot deployment results — (to be added by Fleet Ops, SC-110…SC-115)
- Final production sign-off — (to be added at RRR)

## Branch strategy

```text
validation-candidate-v1 (tag)
        │
        ▼
Hardware Validation Branch
        │
        ├── Only bug fixes from hardware findings
        │
        ▼
validation-candidate-v2 (if needed)
        │
        ▼
Pilot Deployment
        │
        ▼
release-v5.5.0
```

Do not add unrelated improvements or feature work to this line until the
updater is production-qualified.
