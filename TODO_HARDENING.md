# 📋 Production Hardening To-Do List

## Priority 0: Performance & Scaling
- [ ] **Load Test Simulation:** Create `scripts/load_test.py` to simulate 1,000 concurrent scans.
- [ ] **Firestore Optimization:** Audit and ensure all high-frequency writes use `merge=True` or `BatchedWrites`.
- [x] **Async Everything:** All services migrated to `AsyncClient` (Completed).

## Priority 1: Reliability & Observability
- [x] **IT Alerting Integration:** Implement a "Stale Board Watcher" to notify on heartbeat loss.
- [ ] **SLO Definition:** Formally define uptime/latency targets in `docs/ARCHITECTURE.md`.
- [ ] **Error Budgeting:** Add telemetry to track "Error Budget" burn rate.

## Priority 2: Security & Integrity
- [ ] **CI Security Scanning:** Integrate CodeQL/Snyk into `.github/workflows/ci.yml`.
- [ ] **Contract Validation:** Add automated schema alignment tests (Pydantic <-> Isar).
- [x] **Strict Binding:** Hardware-to-JWT binding enforced in interceptors (Completed).

## Priority 3: UI/UX & E2E
- [ ] **Automated UI Tests:** Add `Patrol` or `IntegrationTest` for Kiosk UX flows.
- [x] **Zero-Trust Cleanup:** Removed plaintext backups and legacy custom tokens (Completed).
