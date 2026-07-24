import 'dart:convert';

import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StateOwner
//
// Documents which process is the sole writer for each state file.
// This prevents simultaneous writes from the app and the update agent.
//
// Ownership rules:
//   installation_state.json  → StateOwner.app  (only the app writes)
//   update_state.json        → StateOwner.app  creates it
//                             → StateOwner.agent takes ownership after launch
//                             → StateOwner.app reclaims on agent exit/restart
//   update_health.json       → StateOwner.app  (only the app writes)
// ─────────────────────────────────────────────────────────────────────────────

/// Identifies which process owns write access to a state file.
enum StateOwner {
  /// The Flutter application is the sole writer.
  app,

  /// The detached update agent is the sole writer.
  agent,
}

// ─────────────────────────────────────────────────────────────────────────────
// InstallationState
//
// Tracks the lifecycle of the installation on this machine.
// Persisted to `Data/installation_state.json` (owned by StateOwner.app).
// ─────────────────────────────────────────────────────────────────────────────

enum InstallationState {
  /// MSI just completed; first launch.
  fresh,

  /// Files copied; not yet configured or registered.
  installed,

  /// Board registered with server.
  registered,

  /// Config loaded, env validated.
  configured,

  /// Fully operational.
  operational,

  /// Update in progress.
  updating,

  /// Update completed; version is stable (3+ successful starts).
  healthy,

  /// Something went wrong; in recovery mode.
  recovery,
}

// ─────────────────────────────────────────────────────────────────────────────
// UpdateState
//
// Tracks the lifecycle of an update operation.
// Persisted to `Data/update_state.json`.
//
// Ownership transitions:
//   App creates file with state=verified → launches agent → exits
//   Agent takes ownership, transitions waitingExit → installing → installed → restarting
//   App reclaims ownership on next launch
// ─────────────────────────────────────────────────────────────────────────────

enum UpdateState {
  /// No update in progress.
  idle,

  /// MSI being downloaded from server.
  downloading,

  /// Download complete; awaiting SHA-256 + signature verification.
  downloaded,

  /// Integrity verified; ready to hand off to agent.
  verified,

  /// Agent is waiting for the application process to exit.
  waitingExit,

  /// msiexec is running.
  installing,

  /// msiexec completed; new version is on disk.
  installed,

  /// Agent is launching the new application binary.
  restarting,

  /// Update failed at some stage.
  failed,

  /// Rolling back to previous version.
  rollback,
}

/// Schema version for UpdateStateFile JSON format.
///
/// When the on-disk format changes, increment this value. Readers use it
/// to handle backward-compatible deserialization.
const int updateStateSchemaVersion = 1;

/// The on-disk contract between the Flutter application and the detached
/// update agent.
///
/// Ownership model:
///   1. App creates file with state=`verified`
///   2. App launches agent and exits → agent takes ownership
///   3. Agent transitions: `waitingExit` → `installing` → `installed` → `restarting`
///   4. App reclaims ownership on next launch
///   5. If agent crashes, app reads stale state and retries or rolls back
///
/// Checksum: Every write includes an integrity checksum. If the file is
/// corrupted (crash, power loss, disk error), the reader detects the
/// mismatch and treats the state as stale/corrupt.
class UpdateStateFile {
  /// Absolute path to the downloaded MSI.
  final String msiPath;

  /// Target version string (e.g. "5.6.0+12").
  final String targetVersion;

  /// Expected SHA-256 hex digest of the MSI.
  final String expectedSha256;

  /// PID of the application process the agent should wait for.
  final int appPid;

  /// Absolute path to the application executable.
  final String appExePath;

  /// Absolute path to the agent's log file.
  final String logPath;

  /// Current state of the update operation.
  final UpdateState state;

  /// Human-readable error message if state is `failed`.
  final String? error;

  /// ISO-8601 timestamp when this state file was created.
  final String createdAt;

  /// ISO-8601 timestamp when the operation completed (success or failure).
  final String? completedAt;

  /// Attempt number (1-indexed). Agent increments on retry.
  final int attempt;

  const UpdateStateFile({
    required this.msiPath,
    required this.targetVersion,
    required this.expectedSha256,
    required this.appPid,
    required this.appExePath,
    required this.logPath,
    required this.state,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.attempt = 1,
  });

  UpdateStateFile copyWith({
    UpdateState? state,
    String? error,
    String? completedAt,
    int? attempt,
  }) {
    return UpdateStateFile(
      msiPath: msiPath,
      targetVersion: targetVersion,
      expectedSha256: expectedSha256,
      appPid: appPid,
      appExePath: appExePath,
      logPath: logPath,
      state: state ?? this.state,
      error: error ?? this.error,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      attempt: attempt ?? this.attempt,
    );
  }

  // ── Serialization ──────────────────────────────────────────────────────

  /// Serialize to a map WITHOUT checksum (used to compute the checksum).
  Map<String, dynamic> _toJsonForChecksum() => {
        'schema': updateStateSchemaVersion,
        'msi_path': msiPath,
        'target_version': targetVersion,
        'expected_sha256': expectedSha256,
        'app_pid': appPid,
        'app_exe_path': appExePath,
        'log_path': logPath,
        'state': state.name,
        if (error != null) 'error': error,
        'created_at': createdAt,
        if (completedAt != null) 'completed_at': completedAt,
        'attempt': attempt,
      };

  /// Serialize to a full JSON map including checksum.
  Map<String, dynamic> toJson() {
    final data = _toJsonForChecksum();
    final payload = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(payload)).toString();
    return {
      ...data,
      'checksum': checksum,
    };
  }

  factory UpdateStateFile.fromJson(Map<String, dynamic> json) {
    return UpdateStateFile(
      msiPath: json['msi_path'] as String? ?? '',
      targetVersion: json['target_version'] as String? ?? '',
      expectedSha256: json['expected_sha256'] as String? ?? '',
      appPid: json['app_pid'] as int? ?? 0,
      appExePath: json['app_exe_path'] as String? ?? '',
      logPath: json['log_path'] as String? ?? '',
      state: UpdateState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => UpdateState.idle,
      ),
      error: json['error'] as String?,
      createdAt:
          json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      completedAt: json['completed_at'] as String?,
      attempt: json['attempt'] as int? ?? 1,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decode and validate checksum. Returns `null` if the file is corrupt
  /// or if the checksum doesn't match.
  static UpdateStateFile? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Verify schema version.
      final schema = json['schema'] as int? ?? 0;
      if (schema > updateStateSchemaVersion) {
        // Future schema we don't understand yet.
        return null;
      }

      // Verify checksum.
      final storedChecksum = json['checksum'] as String?;
      if (storedChecksum != null) {
        final dataMap = Map<String, dynamic>.from(json)..remove('checksum');
        final payload = jsonEncode(dataMap);
        final computedChecksum =
            sha256.convert(utf8.encode(payload)).toString();
        if (storedChecksum != computedChecksum) {
          return null; // Corrupted — caller should treat as stale.
        }
      }

      return UpdateStateFile.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Whether the agent is still working (not idle, not failed, not completed).
  bool get isInProgress =>
      state != UpdateState.idle &&
      state != UpdateState.failed &&
      state != UpdateState.installed;

  @override
  String toString() =>
      'UpdateStateFile(v$targetVersion, state=${state.name}, attempt=$attempt)';
}

/// Schema version for installation state JSON format.
const int installationStateSchemaVersion = 1;

/// Wrapper for the installation state file with schema version and checksum.
class InstallationStateFile {
  /// Current installation lifecycle state.
  final InstallationState state;

  /// Optional human-readable detail about the current state.
  final String? detail;

  /// ISO-8601 timestamp of last state change.
  final String updatedAt;

  const InstallationStateFile({
    required this.state,
    this.detail,
    required this.updatedAt,
  });

  /// Serialize to a full JSON map including checksum.
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'schema': installationStateSchemaVersion,
      'state': state.name,
      'detail': detail,
      'updated_at': updatedAt,
    };
    final payload = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(payload)).toString();
    return {
      ...data,
      'checksum': checksum,
    };
  }

  factory InstallationStateFile.fromJson(Map<String, dynamic> json) {
    return InstallationStateFile(
      state: InstallationState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => InstallationState.fresh,
      ),
      detail: json['detail'] as String?,
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  /// Decode and validate checksum. Returns `null` if corrupt.
  static InstallationStateFile? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final schema = json['schema'] as int? ?? 0;
      if (schema > installationStateSchemaVersion) return null;

      final storedChecksum = json['checksum'] as String?;
      if (storedChecksum != null) {
        final dataMap = Map<String, dynamic>.from(json)..remove('checksum');
        final payload = jsonEncode(dataMap);
        final computedChecksum =
            sha256.convert(utf8.encode(payload)).toString();
        if (storedChecksum != computedChecksum) return null;
      }

      return InstallationStateFile.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'InstallationStateFile(${state.name}, detail=$detail)';
}
