import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

import '../lifecycle/lifecycle_phase.dart';
import '../utils/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ObservabilityManager
//
// Unified telemetry facade. Wraps Sentry for cloud crash reporting and
// performance monitoring, while leaving local diagnostics (Event Viewer,
// install journal, structured logs) untouched.
//
// ── Architecture ─────────────────────────────────────────────────────────────
//
//   ObservabilityManager
//     ├─ Sentry (cloud)        — crash reports, performance, release tracking
//     ├─ Local Logs (disk)     — structured JSON logs (Logger)
//     ├─ Event Viewer (OS)     — Windows Event Log entries
//     ├─ Install Journal (C++) — update transaction history
//     └─ Recovery State (disk) — recovery diagnostics
//
// Sentry is the cloud layer. Everything else stays local and works offline.
//
// ── Data Policy ──────────────────────────────────────────────────────────────
//
// Sentry receives:
//   ✓ Unhandled exceptions and lifecycle failures
//   ✓ Performance spans (startup, update, recovery)
//   ✓ Breadcrumbs (state transitions)
//   ✓ Tags (board ID, version, channel, OS)
//
// Sentry does NOT receive:
//   ✗ Student names or attendance data
//   ✗ Faculty names or session data
//   ✗ JWTs, OTPs, or access tokens
//   ✗ GPS coordinates
//   ✗ Personally identifiable information
//
// ─────────────────────────────────────────────────────────────────────────────
class ObservabilityManager {
  ObservabilityManager._();

  static bool _initialized = false;
  static String? _dsn;

  // ── Initialisation ──────────────────────────────────────────────────────

  /// Initialise Sentry. Call once at app startup, before any other
  /// Sentry operations. The [dsn] is the Sentry project DSN. If null
  /// or empty, Sentry is disabled (development/offline mode).
  static Future<void> init({String? dsn}) async {
    if (_initialized) return;
    _dsn = dsn;

    if (dsn == null || dsn.isEmpty) {
      Log.d('[Observability] Sentry disabled (no DSN)');
      return;
    }

    try {
      await Sentry.init(
        (options) {
          options.dsn = dsn;
          options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
          options.environment = kReleaseMode ? 'production' : 'development';
          options.attachStacktrace = true;
          options.maxBreadcrumbs = 100;
          options.sendDefaultPii = false;
        },
      );
      _initialized = true;
      Log.i('[Observability] Sentry initialised');
    } catch (e) {
      Log.w('[Observability] Sentry init failed: $e');
    }
  }

  static bool get isEnabled => _initialized && _dsn != null;

  // ── Tags ────────────────────────────────────────────────────────────────

  /// Set global tags applied to every Sentry event.
  static void setTags(Map<String, String> tags) {
    if (!isEnabled) return;
    Sentry.configureScope((scope) {
      for (final entry in tags.entries) {
        scope.setTag(entry.key, entry.value);
      }
    });
  }

  /// Set the board ID as a global tag.
  static void setBoardId(String boardId) {
    setTags({'board.id': boardId});
  }

  /// Set the app version as a global tag.
  static void setAppVersion(String version) {
    setTags({'app.version': version});
  }

  /// Set the release channel as a global tag.
  static void setChannel(String channel) {
    setTags({'release.channel': channel});
  }

  /// Set the current lifecycle phase as a tag.
  static void setLifecyclePhase(AppLifecyclePhase phase) {
    setTags({'lifecycle.phase': phase.name});
  }

  /// Set the OS version as a global tag.
  static void setOsVersion(String osVersion) {
    setTags({'os.version': osVersion});
  }

  /// Set the update version as a global tag (version being updated to).
  static void setUpdateVersion(String version) {
    setTags({'update.version': version});
  }

  /// Set the recovery type as a global tag.
  static void setRecoveryType(String type) {
    setTags({'recovery.type': type});
  }

  /// Set the deployment identifier as a global tag.
  ///
  /// This is a globally unique identifier for cross-customer fleet filtering.
  /// Example: `mrcet-prod`, `customer-001`.
  static void setDeploymentId(String deploymentId) {
    setTags({'deployment.id': deploymentId});
  }

  /// Set the current update state as a global tag.
  ///
  /// Values: `idle`, `downloading`, `verifying`, `installing`, `completed`,
  /// `failed`. Updated automatically when [AutoUpdater.progress] changes.
  static void setUpdateState(String state) {
    setTags({'update.state': state});
  }

  /// Set build metadata tags from compile-time defines.
  ///
  /// These are injected via `--dart-define` at build time:
  ///   flutter build windows \
  ///     --dart-define=BUILD_NUMBER=42 \
  ///     --dart-define=GIT_COMMIT=abc123
  ///
  /// `build.date` is NOT set as a tag (high cardinality) — it is attached
  /// as event-level context via [setBuildDate] instead.
  ///
  /// Missing defines are silently skipped (no tag set).
  static void setReleaseMetadata({
    String? buildNumber,
    String? gitCommit,
  }) {
    final tags = <String, String>{};
    if (buildNumber != null && buildNumber.isNotEmpty) {
      tags['build.number'] = buildNumber;
    }
    if (gitCommit != null && gitCommit.isNotEmpty) {
      tags['git.commit'] = gitCommit;
    }
    if (tags.isNotEmpty) setTags(tags);
  }

  /// Attach build date as event-level context (not a tag).
  ///
  /// High-cardinality values like timestamps belong in event context,
  /// not as filterable tags. This avoids inflating the tag cardinality
  /// space while still preserving the information for investigation.
  static void setBuildDate(String? buildDate) {
    if (buildDate == null || buildDate.isEmpty || !isEnabled) return;
    Sentry.configureScope((scope) {
      scope.setContexts('build', {'date': buildDate});
    });
  }

  /// Set physical location tags for fleet-scale filtering.
  ///
  /// Tags set: `board.school`, `board.building`, `board.room`.
  /// These are operational identifiers only — never student PII.
  static void setLocation({
    String? school,
    String? building,
    String? room,
  }) {
    final tags = <String, String>{};
    if (school != null && school.isNotEmpty) {
      tags['board.school'] = school;
    }
    if (building != null && building.isNotEmpty) {
      tags['board.building'] = building;
    }
    if (room != null && room.isNotEmpty) {
      tags['board.room'] = room;
    }
    if (tags.isNotEmpty) setTags(tags);
  }

  /// Configure all fleet-scale tags from a single call.
  ///
  /// This is the primary entry point for tag configuration at startup.
  /// It sets board identity, location, version, channel, OS, and deployment
  /// metadata in one atomic operation.
  static void configureFleetTags({
    required String boardId,
    required String appVersion,
    required String channel,
    required String osVersion,
    String? school,
    String? building,
    String? room,
    String? deploymentId,
    String? buildNumber,
    String? gitCommit,
    String? buildDate,
  }) {
    setTags({
      'board.id': boardId,
      'app.version': appVersion,
      'release.channel': channel,
      'os.version': osVersion,
    });
    setLocation(school: school, building: building, room: room);
    if (deploymentId != null && deploymentId.isNotEmpty) {
      setDeploymentId(deploymentId);
    }
    setReleaseMetadata(
      buildNumber: buildNumber,
      gitCommit: gitCommit,
    );
    // build.date is high-cardinality — attach as event context, not tag.
    setBuildDate(buildDate);
  }

  // ── Breadcrumbs ─────────────────────────────────────────────────────────

  /// Record a state-transition breadcrumb. These appear in the crash
  /// report timeline leading up to the error.
  static void breadcrumb(String message, {String category = 'default'}) {
    if (!isEnabled) return;
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      category: category,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  /// Record a lifecycle phase transition.
  static void lifecycleBreadcrumb(AppLifecyclePhase phase, {String? detail}) {
    breadcrumb(
      'Lifecycle: ${phase.name}${detail != null ? ' — $detail' : ''}',
      category: 'lifecycle',
    );
  }

  /// Record an update event.
  static void updateBreadcrumb(String event, {String? detail}) {
    breadcrumb(
      'Update: $event${detail != null ? ' — $detail' : ''}',
      category: 'update',
    );
  }

  /// Record a recovery event.
  static void recoveryBreadcrumb(String event, {String? detail}) {
    breadcrumb(
      'Recovery: $event${detail != null ? ' — $detail' : ''}',
      category: 'recovery',
    );
  }

  // ── Performance Spans ───────────────────────────────────────────────────

  /// Start a performance transaction. Returns a [SentrySpan] that must
  /// be finished by the caller via [finishTransaction].
  static ISentrySpan? startTransaction(String name, String operation) {
    if (!isEnabled) return null;
    return Sentry.startTransaction(name, operation);
  }

  /// Record a lifecycle phase as a performance span with measurements.
  ///
  /// Measurements are numeric values attached to the transaction, visible
  /// in Sentry's Performance tab. Unlike tags (which tell you **what** the
  /// board is), measurements tell you **how well** it's performing.
  static Future<void> recordLifecyclePhase({
    required AppLifecyclePhase phase,
    required Duration duration,
    required bool success,
  }) async {
    if (!isEnabled) return;
    final tx = Sentry.startTransaction('lifecycle.${phase.name}', 'other');
    tx.setData('phase', phase.name);
    tx.setData('duration_ms', duration.inMilliseconds);
    tx.setData('success', success);
    await tx.finish(
      status: success ? SpanStatus.ok() : SpanStatus.internalError(),
    );
  }

  /// Record a custom measurement (numeric metric) on the current scope.
  ///
  /// Measurements complement tags: tags identify **what** the board is,
  /// measurements quantify **how** it's performing.
  ///
  /// Examples:
  ///   setMeasurement('startup.time_ms', 1840)
  ///   setMeasurement('recovery.time_ms', 420)
  ///   setMeasurement('manifest.validation_ms', 15)
  ///   setMeasurement('download.size_mb', 42)
  static void setMeasurement(String name, num value) {
    if (!isEnabled) return;
    Sentry.configureScope((scope) {
      scope.setContexts('measurement', {name: value});
    });
  }

  // ── Errors ──────────────────────────────────────────────────────────────

  /// Capture an exception with optional context.
  static Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    Map<String, String>? tags,
    Map<String, dynamic>? extra,
  }) async {
    if (!isEnabled) return;
    final hint = Hint.withMap({
      if (tags != null) 'tags': tags,
      if (extra != null) 'extra': extra,
    });
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      hint: hint,
    );
  }

  /// Capture a message (non-exception event).
  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
  }) async {
    if (!isEnabled) return;
    await Sentry.captureMessage(message, level: level);
  }

  // ── Flush / Close ───────────────────────────────────────────────────────

  /// Flush pending events before shutdown.
  static Future<void> flush() async {
    if (!isEnabled) return;
    // Sentry handles flushing automatically on close.
    // This method exists for API symmetry with other managers.
  }

  /// Close the Sentry client.
  static Future<void> close() async {
    if (!isEnabled) return;
    await Sentry.close();
  }
}
