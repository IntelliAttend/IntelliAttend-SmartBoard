import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../config/install_paths.dart';
import '../utils/logger.dart';
import 'installation_state.dart';

/// Schema version for installation context JSON format.
const int installationContextSchemaVersion = 1;

/// Immutable snapshot of the application's identity and installation metadata.
///
/// Loaded once at startup and read by every subsystem that needs to know
/// "who am I, what version, how did I get here." Nothing writes to this
/// directly — mutations go through [StatePersister] and are reloaded on
/// next startup.
///
/// This object replaces the scattered `Version.current`, `boardId`, etc.
/// lookups that previously lived in 15+ files.
class InstallationContext {
  /// The version of the currently running executable.
  final String currentVersion;

  /// The version reported by the server as "installed" (may lag behind
  /// currentVersion if the update just happened).
  final String installedVersion;

  /// The version before the most recent update (null if never updated).
  final String? previousVersion;

  /// ISO-8601 timestamp when this installation was first created.
  final String installDate;

  /// ISO-8601 timestamp when the last successful update completed.
  final String? lastUpdateTime;

  /// Number of successful updates applied since initial install.
  final int updateCount;

  /// Number of rollbacks that have occurred.
  final int rollbackCount;

  /// Board identifier from server registration.
  final String? boardId;

  /// Current installation lifecycle state.
  final InstallationState installationState;

  /// Human-readable detail about the current state.
  final String? stateDetail;

  const InstallationContext({
    required this.currentVersion,
    required this.installedVersion,
    this.previousVersion,
    required this.installDate,
    this.lastUpdateTime,
    required this.updateCount,
    required this.rollbackCount,
    this.boardId,
    required this.installationState,
    this.stateDetail,
  });

  /// Create a default context for a fresh installation.
  factory InstallationContext.fresh(String version) {
    final now = DateTime.now().toIso8601String();
    return InstallationContext(
      currentVersion: version,
      installedVersion: version,
      previousVersion: null,
      installDate: now,
      lastUpdateTime: null,
      updateCount: 0,
      rollbackCount: 0,
      boardId: null,
      installationState: InstallationState.fresh,
      stateDetail: null,
    );
  }

  /// Load context from the persisted context file. Returns a fresh context
  /// if no file exists or if the file is corrupt.
  factory InstallationContext.load(String currentVersion) {
    try {
      final file = File('${InstallPaths.dataDir}\\installation_context.json');
      if (!file.existsSync()) {
        return InstallationContext.fresh(currentVersion);
      }

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Schema version check.
      final schema = json['schema'] as int? ?? 0;
      if (schema > installationContextSchemaVersion) {
        Log.w('[InstallationContext] Unknown schema v$schema; using fresh');
        return InstallationContext.fresh(currentVersion);
      }

      // Checksum validation.
      final storedChecksum = json['checksum'] as String?;
      if (storedChecksum != null) {
        final dataMap = Map<String, dynamic>.from(json)..remove('checksum');
        final payload = jsonEncode(dataMap);
        final computed =
            sha256.convert(utf8.encode(payload)).toString();
        if (storedChecksum != computed) {
          Log.w('[InstallationContext] Checksum mismatch; using fresh');
          return InstallationContext.fresh(currentVersion);
        }
      }

      return InstallationContext(
        currentVersion: currentVersion,
        installedVersion: json['installed_version'] as String? ?? currentVersion,
        previousVersion: json['previous_version'] as String?,
        installDate: json['install_date'] as String? ?? DateTime.now().toIso8601String(),
        lastUpdateTime: json['last_update_time'] as String?,
        updateCount: json['update_count'] as int? ?? 0,
        rollbackCount: json['rollback_count'] as int? ?? 0,
        boardId: json['board_id'] as String?,
        installationState: InstallationState.values.firstWhere(
          (s) => s.name == json['installation_state'],
          orElse: () => InstallationState.fresh,
        ),
        stateDetail: json['state_detail'] as String?,
      );
    } catch (e) {
      Log.w('[InstallationContext] Failed to load; using fresh: $e');
      return InstallationContext.fresh(currentVersion);
    }
  }

  /// Persist the context to disk. Uses atomic write (temp + rename).
  ///
  /// Note: This is the ONLY place that writes `installation_context.json`.
  /// The update agent must NOT write this file — it is app-owned.
  Future<void> save() async {
    try {
      final file = File('${InstallPaths.dataDir}\\installation_context.json');
      final data = {
        'schema': installationContextSchemaVersion,
        'installed_version': installedVersion,
        'previous_version': previousVersion,
        'install_date': installDate,
        'last_update_time': lastUpdateTime,
        'update_count': updateCount,
        'rollback_count': rollbackCount,
        'board_id': boardId,
        'installation_state': installationState.name,
        'state_detail': stateDetail,
      };
      final payload = jsonEncode(data);
      final checksum = sha256.convert(utf8.encode(payload)).toString();
      final fullData = {
        ...data,
        'checksum': checksum,
      };

      // Atomic write.
      final tempPath =
          '${file.path}.tmp.${DateTime.now().millisecondsSinceEpoch}';
      final tempFile = File(tempPath);
      final encoder = JsonEncoder.withIndent('  ');
      await tempFile.writeAsString(encoder.convert(fullData));
      if (file.existsSync()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } catch (e) {
      Log.w('[InstallationContext] Failed to save: $e');
    }
  }

  /// Create a copy with updated fields. Use this to transition state
  /// without mutating the original.
  InstallationContext copyWith({
    String? installedVersion,
    String? previousVersion,
    String? lastUpdateTime,
    int? updateCount,
    int? rollbackCount,
    String? boardId,
    InstallationState? installationState,
    String? stateDetail,
  }) {
    return InstallationContext(
      currentVersion: currentVersion,
      installedVersion: installedVersion ?? this.installedVersion,
      previousVersion: previousVersion ?? this.previousVersion,
      installDate: installDate,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      updateCount: updateCount ?? this.updateCount,
      rollbackCount: rollbackCount ?? this.rollbackCount,
      boardId: boardId ?? this.boardId,
      installationState: installationState ?? this.installationState,
      stateDetail: stateDetail ?? this.stateDetail,
    );
  }

  @override
  String toString() =>
      'InstallationContext(v$currentVersion, installed=$installedVersion, '
      'state=${installationState.name}, updates=$updateCount, '
      'rollbacks=$rollbackCount, board=$boardId)';
}
