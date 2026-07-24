# Phase 5 — Recovery UI

**Status:** Complete
**Date:** 2026-07-22
**Reviewer Rating:** Pending

---

## 1. Objective

Phase 5 makes failure **visible, understandable, and recoverable**.

The core deployment architecture (Phases 0–4) ensures the system fails
deterministically. Phase 5 ensures the user sees a clear, themed,
actionable recovery interface instead of a blank screen or cryptic error.

The recovery screen replaces the 39-line `InitFailureScreen` with a
production-grade interface that:

- Shows **what** failed and **why**
- Attempts **automatic recovery** when possible
- Gives the user clear **action choices**
- Provides **diagnostic details** for support engineers
- Reflects the **deterministic lifecycle states** already designed

---

## 2. What Changed

### 2.1 RecoveryState (`lib/core/recovery/recovery_state.dart`)

Three types:

**RecoveryType** — classifies the failure:

| Type | Auto-Recoverable | Launch Anyway | Description |
|---|---|---|---|
| `crashLoop` | ✓ | ✓ | Multiple consecutive launch failures |
| `integrityFailure` | ✗ | ✗ | Binary hash/signature mismatch |
| `lifecycleFailure` | ✗ | ✗ | Phase returned error |
| `startupTimeout` | ✗ | ✗ | Watchdog fired after 60s |
| `updateCorruption` | ✓ | ✗ | Interrupted update state |
| `unhandledError` | ✗ | ✗ | Unhandled exception |

**RecoveryPhase** — where recovery is right now:

| Phase | UI Behavior |
|---|---|
| `resolving` | Progress indicator, auto-recovery running |
| `resolved` | Success message, auto-relaunch in 2s |
| `failed` | Action buttons enabled, waiting for user |
| `launching` | "Launching..." message, buttons disabled |
| `closing` | Shutdown in progress |

**RecoveryDiagnostics** — rich context for support:

| Field | Purpose |
|---|---|
| `appVersion` | Version that failed |
| `failedPhase` | Which lifecycle phase crashed |
| `errorMessage` | Human-readable error |
| `crashCount` | Consecutive failures |
| `isAutoStart` | Windows auto-start launch |
| `elapsedMs` | Time before failure |
| `timings` | Per-phase timing data |
| `extra` | Extensible key-value diagnostics |

### 2.2 RecoveryManager (`lib/core/recovery/recovery_manager.dart`)

Singleton state machine. All methods `static`. Drives the recovery
lifecycle:

```
init(type, diagnostics)
  ↓
  ├─ auto-recoverable? → attemptAutoRecovery()
  │     ↓
  │     clean stale state → migration → mark completed → relaunch
  │     ↓
  │     success → RESOLVED → relaunch in 2s
  │     failure → FAILED → wait for user
  │
  └─ not recoverable → FAILED → wait for user

User actions:
  retry()       → RESOLVING → attemptAutoRecovery()
  launchAnyway() → LAUNCHING → onRelaunch callback
  close()       → CLOSING → windowManager.destroy()
```

The manager exposes a `ValueNotifier<RecoveryState>` for the UI.

### 2.3 RecoveryScreen (`lib/presentation/screens/recovery_screen.dart`)

Full-screen recovery UI. Standalone `MaterialApp` (same pattern as
`InitFailureScreen`). Dark theme. Animated pulse icon.

**Layout:**

```
┌──────────────────────────────────────┐
│                                      │
│       [Pulsing Icon]                 │
│                                      │
│    Startup Crash Detected            │
│    v5.5.0+11 · 3 consecutive fails   │
│                                      │
│    ┌─ Attempting recovery... ─────┐  │
│    │  ✓ Cleaning stale state      │  │
│    │  ● Verifying directories...  │  │
│    └──────────────────────────────┘  │
│                                      │
│    ┌─ Diagnostic Details ─────────┐  │
│     │ Failed Phase: validation    │  │
│     │ Error: Integrity check...   │  │
│     │ Version: 5.5.0+11           │  │
│     │ Crashes: 3                  │  │
│     │ Elapsed: 42ms               │  │
│     └─────────────────────────────┘  │
│                                      │
│    ┌─ Phase Timings ──────────────┐  │
│     │ boot         2ms     ✓      │  │
│     │ recovery    15ms     ✓      │  │
│     │ validation  44ms     ✗      │  │
│     └─────────────────────────────┘  │
│                                      │
│    [Retry] [Launch Anyway] [Close]   │
│                                      │
└──────────────────────────────────────┘
```

**Features:**

- Animated pulse icon (teal when resolving, red when failed, green when
  transitioning)
- Collapsible diagnostic details panel (tap to expand)
- Phase timing visualization with ✓/✗ indicators
- Context-sensitive action buttons:
  - `retry()` — always available when awaiting user
  - `launchAnyway()` — only for crash loop recovery
  - `close()` — always available
- Buttons disabled during transitions (resolved/launching/closing)

### 2.4 main.dart Integration

Three integration points replaced `InitFailureScreen`:

**Crash loop handler** (`onCrashLoop`):
```dart
// Before
runApp(InitFailureScreen(message: message));

// After
await _showRecovery(
  type: RecoveryType.crashLoop,
  args: args,
  diagnostics: RecoveryDiagnostics.fromGuard(...),
);
runApp(const RecoveryScreen());
```

**Lifecycle failure** (new — was previously silent):
```dart
if (phase != AppLifecyclePhase.ready) {
  await _showRecovery(
    type: RecoveryType.lifecycleFailure,
    args: args,
    diagnostics: RecoveryDiagnostics.fromFailure(...),
  );
}
```

**Watchdog timeout** (`_startStartupWatchdog`):
```dart
// Before
navigatorKey.currentState?.pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => InitFailureScreen(message: ...)),
  (_) => false,
);

// After
await RecoveryManager.init(type: RecoveryType.startupTimeout, ...);
navigatorKey.currentState?.pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => const RecoveryScreen()),
  (_) => false,
);
```

The new `_showRecovery()` helper centralizes rollback attempt, kiosk
release, and RecoveryManager initialisation.

---

## 3. Recovery Scenarios

### 3.1 Crash Loop → Auto-Recovery

```
Board crashes 3x consecutively
  → Lifecycle detects crash loop
  → RecoveryManager.init(type: crashLoop)
  → Auto-recovery runs:
      clean stale update state
      run path migration
      mark launch completed
  → RESOLVED → relaunch in 2s
  → App starts normally
```

### 3.2 Integrity Failure → Manual Recovery

```
Binary hash mismatch detected
  → Lifecycle returns failed
  → RecoveryManager.init(type: integrityFailure)
  → NOT auto-recoverable → FAILED state
  → User sees:
      "The application files may be corrupted.
       Please reinstall from the installer."
  → User clicks Close → app exits
```

### 3.3 Startup Timeout → Retry

```
Watchdog fires after 60s
  → RecoveryManager.init(type: startupTimeout)
  → NOT auto-recoverable → FAILED state
  → User sees diagnostic details (which phase was stuck)
  → User clicks Retry → recovery runs again
```

### 3.4 Lifecycle Failure → Diagnostics

```
Database initialization fails
  → Lifecycle returns failed
  → RecoveryManager.init(type: lifecycleFailure)
  → User sees:
      Failed Phase: database
      Error: Isar initialization failed
      Phase timings with ✓/✗
  → User clicks Close → app exits
```

---

## 4. Diagnostic Output Example

```
┌─ Phase Timings ─────────────────────┐
│ boot         2ms     ✓              │
│ recovery    15ms     ✓              │
│ validation  44ms     ✗              │
│ (total: 61ms)                       │
└─────────────────────────────────────┘
```

This immediately tells a support engineer:
- Boot and recovery were fine
- Validation failed after 44ms
- Total startup time was 61ms
- The issue is in the validation phase

---

## 5. Files Changed

| File | Action |
|---|---|
| `lib/core/recovery/recovery_state.dart` | **New** — RecoveryType, RecoveryPhase, RecoveryDiagnostics, RecoveryState |
| `lib/core/recovery/recovery_manager.dart` | **New** — singleton state machine |
| `lib/presentation/screens/recovery_screen.dart` | **New** — themed recovery UI |
| `lib/main.dart` | Modified — replaced InitFailureScreen with RecoveryScreen, added lifecycle failure handler |

---

## 6. Acceptance Criteria

- [x] `flutter analyze lib/` — zero new issues
- [x] RecoveryScreen is a standalone MaterialApp (same pattern as InitFailureScreen)
- [x] Dark theme consistent with update overlay
- [x] Animated pulse icon for resolving state
- [x] Diagnostic details panel is collapsible
- [x] Phase timings shown with ✓/✗ indicators
- [x] Action buttons context-sensitive (launchAnyway only for crashLoop)
- [x] Buttons disabled during transitions
- [x] Auto-recovery runs for crashLoop and updateCorruption
- [x] Lifecycle failures (validation, database) now show recovery UI (was silent)
- [x] Watchdog timeout uses RecoveryScreen
- [x] RecoveryManager exposes ValueNotifier for reactive UI
- [x] All recovery types have appropriate human-readable messages
