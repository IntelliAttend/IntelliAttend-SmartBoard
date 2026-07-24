# Phase 7 — Cloud Observability & Diagnostics Specification

**Version**: 1.0  
**Status**: Complete  
**Phase**: 7 of 12  
**Architecture Freeze**: Applies (Phase 0–6 frozen; this phase extends, does not replace)

---

## 1. Purpose

Phase 7 adds cloud-based observability and local diagnostic export to the SmartBoard application. It provides three capabilities:

1. **Sentry telemetry** — crash reporting, performance tracing, breadcrumbs
2. **Health snapshots** — point-in-time application state for diagnostics
3. **Diagnostic bundles** — ZIP exports for offline support analysis

---

## 2. Design Principles

| # | Principle | Rationale |
|---|-----------|-----------|
| 1 | **No new architectural layers** | Sentry integration wraps existing surfaces; no new state machines, no new UI screens |
| 2 | **Privacy by default** | `sendDefaultPii = false`; board ID is opaque UUID, not personally identifiable |
| 3 | **Fail silently** | Observability failures must never crash the application or block user workflows |
| 4 | **Offline-capable** | Health snapshots and diagnostic bundles work without network; Sentry buffers locally when offline |
| 5 | **Release-gated** | Low sample rates in production (20% traces, 10% profiles) to control costs |

---

## 3. Components

### 3.1 ObservabilityManager (`lib/core/observability/observability_manager.dart`)

Unified telemetry facade wrapping Sentry SDK. All observability calls go through this class.

**API surface:**

| Method | Purpose |
|--------|---------|
| `init(dsn)` | Initialise Sentry with config; no-op if DSN missing |
| `setTags(Map)` | Attach multiple tags atomically |
| `setBoardId(id)` | Set board identity tag |
| `setAppVersion(version)` | Set app version tag |
| `setChannel(channel)` | Set release channel tag |
| `setOsVersion(os)` | Set OS version tag |
| `setLifecyclePhase(phase)` | Set current lifecycle phase tag |
| `setUpdateVersion(version)` | Set version being updated to |
| `setRecoveryType(type)` | Set active recovery type tag |
| `setLocation({school, building, room})` | Set physical location tags for fleet filtering |
| `configureFleetTags(...)` | Set all fleet-scale tags in one atomic call |
| `breadcrumb(message, {category, data})` | Structured event trail (100 max) |
| `startTransaction(name, operation)` | Performance span for lifecycle phases |
| `captureException(error, {stackTrace, hint})` | Report error with context |
| `flush()` | Ensure pending events are sent before exit |
| `close()` | Shut down Sentry cleanly |

**Configuration (production):**

| Setting | Value | Rationale |
|---------|-------|-----------|
| `tracesSampleRate` | 0.2 | 20% of transactions traced; controls cost |
| `attachStacktrace` | `true` | Full stack traces on all exceptions |
| `maxBreadcrumbs` | 100 | Last 100 events before error |
| `sendDefaultPii` | `false` | No IP, no user data |
| `environment` | `production` / `development` | Based on `kReleaseMode` |

**Tags applied at init (via `configureFleetTags`):**

| Tag | Value | Source | Filter Use |
|-----|-------|--------|------------|
| `board.id` | Opaque ID (e.g. `MRCET-A-102`) | `registration.smartBoardId` | Find specific board |
| `board.school` | School name (e.g. `MRCET`) | `deploy_config.json → location.school` | Filter by school |
| `board.building` | Building ID (e.g. `Block A`) | `deploy_config.json → location.building` | Filter by building |
| `board.room` | Room ID (e.g. `A-204`) | `deploy_config.json → location.room` | Filter by room |
| `app.version` | `x.y.z+build` | `AppLifecycleManager.appVersion` | Release comparison |
| `release.channel` | `stable` / `beta` / `dev` | `deploy_config.json → update.channel` | Channel filtering |
| `os.version` | `11 24H2` | `Platform.operatingSystemVersion` | OS-specific issues |
| `lifecycle.phase` | Current phase name | Updated on each phase transition | Phase-specific crashes |
| `recovery.type` | Active recovery type | Updated on recovery state change | Recovery filtering |
| `update.version` | Version being updated to | Set before update download | Post-update regressions |

**Breadcrumbs emitted:**

| Source | Breadcrumb Category | Example |
|--------|-------------------|---------|
| `AppLifecycleManager` | `lifecycle.phase` | `BOOT → RECOVERY → VALIDATION → ... → READY` |
| `RecoveryManager` | `recovery.state` | `crashLoop → resolving → resolved` |
| `AutoUpdater` | `update.denied` | Manifest policy rejection reasons |

### 3.2 HealthSnapshot (`lib/core/observability/health_snapshot.dart`)

Point-in-time view of application health, aggregating state from all subsystems.

**Data collected:**

| Field | Source | Description |
|-------|--------|-------------|
| `timestamp` | `DateTime.now()` | When snapshot was taken |
| `boardId` | `InstallationContext` | Opaque board identifier |
| `appVersion` | `InstallationContext` | Current version string |
| `lifecycle` | `AppLifecycleManager` | Current phase, completed phases, failed phases |
| `update` | `AutoUpdater` | Last check time, last version, pending version, rollout phase |
| `recovery` | `RecoveryManager` | Active recovery type/phase, diagnostics, timestamps |
| `disk` | `InstallPaths` | App size, data size, cache size (bytes) |
| `platform` | `Platform` | OS version, locale, temp directory |

**Usage:**

- Included in every diagnostic bundle (`health.json`)
- Returned by `HealthSnapshot.capture()` for ad-hoc inspection
- Sent as Sentry event context via `setTag`/`setExtra`

### 3.3 DiagnosticBundle (`lib/core/observability/diagnostic_bundle.dart`)

ZIP export containing all diagnostic data for offline support analysis.

**Contents:**

| File | Source | Format |
|------|--------|--------|
| `health.json` | `HealthSnapshot.capture()` | JSON |
| `lifecycle.json` | `AppLifecycleManager.toJson()` | JSON |
| `environment.json` | `Platform` + `InstallPaths` | JSON |
| `config_summary.json` | `EnterpriseDeployConfig` (redacted) | JSON |
| `logs/*.log` | `InstallPaths.logsDir` | Text (last 7 days) |
| `update_journal.json` | Update agent journal | JSON |
| `recovery_state.json` | `RecoveryManager.state` | JSON |

**Privacy controls:**

- `config_summary.json` redacts all secrets, API keys, tokens
- Only logs from the last 7 days are included
- No user data, no credentials, no signing keys

**API:**

```dart
final bundle = DiagnosticBundle();
final zipPath = await bundle.export();  // Returns path to ZIP
```

---

## 4. Integration Points

### 4.1 main.dart

```dart
// Init (after registration, before lifecycle)
await ObservabilityManager.init(
  Platform.environment['SENTRY_DSN'] ?? '',
);
ObservabilityManager.setTag('board.id', boardId);
ObservabilityManager.setTag('app.version', appVersion);

// Error handler
}, (Object error, StackTrace stack) {
  ObservabilityManager.captureException(error, stackTrace: stack);
  // ... existing recovery ...
});

// Exit (before runApp completes)
ObservabilityManager.flush();
```

### 4.2 AppLifecycleManager

Each phase transition emits a breadcrumb:

```dart
ObservabilityManager.addBreadcrumb(
  'Phase ${phase.name} completed',
  category: 'lifecycle.phase',
  data: {'phase': phase.name, 'elapsed': timing.elapsedMs},
);
```

### 4.3 RecoveryManager

Recovery state transitions emit breadcrumbs:

```dart
ObservabilityManager.addBreadcrumb(
  'Recovery: ${state.type.name} → ${state.phase.name}',
  category: 'recovery.state',
  data: {'type': state.type.name, 'phase': state.phase.name},
);
```

### 4.4 AutoUpdater

Manifest policy denials are tracked:

```dart
ObservabilityManager.addBreadcrumb(
  'Update denied: ${reason}',
  category: 'update.denied',
  data: {'reason': reason, 'manifest': manifest.toJson()},
);
```

---

## 5. Data Flow

```
┌─────────────────────────────────────────────────┐
│                  SmartBoard App                  │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐             │
│  │   Lifecycle   │  │   Recovery   │             │
│  │   Manager     │  │   Manager    │             │
│  └──────┬───────┘  └──────┬───────┘             │
│         │                 │                     │
│         ▼                 ▼                     │
│  ┌─────────────────────────────┐               │
│  │    ObservabilityManager     │               │
│  │    (Sentry wrapper)         │               │
│  └─────────────┬───────────────┘               │
│                │                                │
│         ┌──────┴──────┐                        │
│         ▼             ▼                        │
│  ┌──────────┐  ┌──────────────┐                │
│  │ Health   │  │ Diagnostic   │                │
│  │ Snapshot │  │ Bundle (ZIP) │                │
│  └──────────┘  └──────────────┘                │
│                                                 │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │   Sentry.io  │
              │   (cloud)    │
              └──────────────┘
```

---

## 6. Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SENTRY_DSN` | No | (empty) | Sentry project DSN; if empty, telemetry is disabled |

### Privacy

| Control | Value | Rationale |
|---------|-------|-----------|
| `sendDefaultPii` | `false` | No IP, no user agent, no cookies |
| `tracesSampleRate` | 0.2 | Cost control; full tracing only in dev |
| Board ID | UUID | Opaque; not tied to any personal identifier |
| Diagnostic bundle | Redacted | All secrets stripped before export |

---

## 7. Error Handling

| Scenario | Behaviour |
|----------|-----------|
| DSN missing | `init()` returns; all other methods are no-ops |
| Sentry init fails | Logged; app continues without telemetry |
| `captureException` fails | Caught internally; never propagates |
| `flush()` fails | Caught internally; app exits normally |
| Diagnostic bundle export fails | Returns `null`; caller handles gracefully |
| ZIP creation fails (e.g., disk full) | Returns `null`; error logged locally |

---

## 8. Testing

### Unit Tests

| Test | Validates |
|------|-----------|
| `ObservabilityManager` init with/without DSN | Graceful degradation |
| `ObservabilityManager` breadcrumb buffering | Breadcrumbs stored until flush |
| `HealthSnapshot.capture()` | All subsystems represented |
| `DiagnosticBundle.export()` | ZIP contains expected files |
| `DiagnosticBundle.export()` redaction | No secrets in output |

### Integration Tests

| Test | Validates |
|------|-----------|
| Full lifecycle with Sentry enabled | Breadcrumbs match phase transitions |
| Recovery flow with Sentry enabled | Recovery breadcrumbs emitted |
| Diagnostic bundle after error | Bundle contains error context |

---

## 9. Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Sentry integrates via `ObservabilityManager` (not raw SDK) | ✅ |
| 2 | DSN missing → graceful no-op, no crash | ✅ |
| 3 | `sendDefaultPii = false` | ✅ |
| 4 | Board ID is opaque, not PII | ✅ |
| 5 | Lifecycle phases emit breadcrumbs | ✅ |
| 6 | Recovery state transitions emit breadcrumbs | ✅ |
| 7 | `HealthSnapshot` captures all subsystem state | ✅ |
| 8 | `DiagnosticBundle` exports ZIP with redacted config | ✅ |
| 9 | `flush()` called before app exit | ✅ |
| 10 | Zero new analyzer issues | ✅ |
| 11 | No new architectural layers (only wraps existing) | ✅ |
| 12 | Observability failures never crash the app | ✅ |
| 13 | Fleet-scale tags: school, building, room, OS, channel | ✅ |
| 14 | `configureFleetTags()` sets all tags in one atomic call | ✅ |
| 15 | Location metadata sourced from `deploy_config.json` | ✅ |

---

## 10. Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `lib/core/observability/observability_manager.dart` | **New** | Sentry wrapper facade with fleet-scale tags |
| `lib/core/observability/health_snapshot.dart` | **New** | Point-in-time health view |
| `lib/core/observability/diagnostic_bundle.dart` | **New** | ZIP export for support |
| `lib/core/config/enterprise_deploy_config.dart` | Modified | Added `LocationConfig` (school, building, room) |
| `config/enterprise_config_schema.json` | Modified | Added `location` object to JSON schema |
| `pubspec.yaml` | Modified | Added `sentry: ^8.14.2`, `sentry_flutter: ^8.14.1` |
| `lib/main.dart` | Modified | Init Sentry, configure fleet tags from deploy_config, capture errors, flush on exit |
| `lib/core/lifecycle/app_lifecycle_manager.dart` | Modified | Emit lifecycle breadcrumbs |
| `lib/core/recovery/recovery_manager.dart` | Modified | Emit recovery breadcrumbs |
| `lib/services/auto_updater.dart` | Modified | Emit update denial breadcrumbs |
