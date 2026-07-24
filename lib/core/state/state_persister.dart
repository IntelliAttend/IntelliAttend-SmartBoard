import 'dart:convert';
import 'dart:io';

import '../config/install_paths.dart';
import '../utils/logger.dart';
import 'installation_state.dart';

/// Persists installation and update state to disk.
///
/// State files survive crashes, power loss, and reboots because they are
/// written atomically (write to temp, then rename).
///
/// Ownership model:
///   - `installation_state.json` → only the Flutter app writes
///   - `update_state.json` → app creates, agent takes over, app reclaims
///
/// Every read validates the checksum. If corruption is detected, safe
/// defaults are returned so the app can enter recovery mode.
class StatePersister {
  StatePersister._();

  // ── Installation state ──────────────────────────────────────────────────

  /// Persist the current installation lifecycle state.
  static Future<void> saveInstallationState(
    InstallationState state, {
    String? detail,
  }) async {
    try {
      final file = InstallPaths.installationStateFileInstance;
      final stateFile = InstallationStateFile(
        state: state,
        detail: detail,
        updatedAt: DateTime.now().toIso8601String(),
      );
      await _atomicWrite(file, stateFile.toJson());
    } catch (e) {
      Log.w('[StatePersister] Failed to save installation state: $e');
    }
  }

  /// Load the persisted installation state. Returns [InstallationState.fresh]
  /// if no state file exists (first launch) or if the file is corrupt.
  static Future<InstallationState> loadInstallationState() async {
    try {
      final file = InstallPaths.installationStateFileInstance;
      if (!file.existsSync()) return InstallationState.fresh;

      final content = file.readAsStringSync();
      final stateFile = InstallationStateFile.decode(content);
      if (stateFile == null) {
        Log.w('[StatePersister] Installation state file corrupt; using fresh');
        return InstallationState.fresh;
      }

      return stateFile.state;
    } catch (e) {
      Log.w('[StatePersister] Failed to load installation state: $e');
      return InstallationState.fresh;
    }
  }

  /// Load full installation state file with all metadata.
  static Future<InstallationStateFile?> loadInstallationStateFile() async {
    try {
      final file = InstallPaths.installationStateFileInstance;
      if (!file.existsSync()) return null;

      final content = file.readAsStringSync();
      return InstallationStateFile.decode(content);
    } catch (e) {
      Log.w('[StatePersister] Failed to load installation state file: $e');
      return null;
    }
  }

  // ── Update state ────────────────────────────────────────────────────────

  /// Persist the current update operation state.
  static Future<void> saveUpdateState(UpdateStateFile state) async {
    try {
      final file = InstallPaths.updateStateFileInstance;
      await _atomicWrite(file, state.toJson());
    } catch (e) {
      Log.w('[StatePersister] Failed to save update state: $e');
    }
  }

  /// Load the persisted update state. Returns `null` if no state file exists,
  /// if the file is corrupt, or if the checksum doesn't match.
  static Future<UpdateStateFile?> loadUpdateState() async {
    try {
      final file = InstallPaths.updateStateFileInstance;
      if (!file.existsSync()) return null;

      final content = file.readAsStringSync();
      final stateFile = UpdateStateFile.decode(content);
      if (stateFile == null) {
        Log.w('[StatePersister] Update state file corrupt or checksum mismatch');
      }
      return stateFile;
    } catch (e) {
      Log.w('[StatePersister] Failed to load update state: $e');
      return null;
    }
  }

  /// Delete the update state file. Called after an update completes
  /// successfully or after a rollback finishes.
  static Future<void> clearUpdateState() async {
    try {
      final file = InstallPaths.updateStateFileInstance;
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      Log.w('[StatePersister] Failed to clear update state: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Atomic write: write to a temporary file, then rename. This prevents
  /// corrupt state files if the process crashes mid-write.
  static Future<void> _atomicWrite(
    File target,
    Map<String, dynamic> data,
  ) async {
    final tempPath =
        '${target.path}.tmp.${DateTime.now().millisecondsSinceEpoch}';
    final tempFile = File(tempPath);

    try {
      final encoder = JsonEncoder.withIndent('  ');
      await tempFile.writeAsString(encoder.convert(data));

      // On Windows, rename fails if destination exists. Delete first.
      if (target.existsSync()) {
        await target.delete();
      }
      await tempFile.rename(target.path);
    } catch (e) {
      // Clean up temp file on failure.
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
