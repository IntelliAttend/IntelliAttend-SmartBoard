import '../config/install_paths.dart';
import '../startup/path_migration.dart';
import '../startup_service.dart';
import '../state/installation_state.dart';
import '../utils/logger.dart';

/// Lifecycle recovery operations.
///
/// These are separated from the main lifecycle manager to keep
/// each file focused and testable.
class LifecycleRecover {
  LifecycleRecover._();

  /// Recover from stale update state left by the agent.
  static Future<void> recoverFromStaleUpdateState() async {
    try {
      final stateFile = InstallPaths.updateStateFileInstance;
      if (!stateFile.existsSync()) return;

      final content = stateFile.readAsStringSync();
      final state = UpdateStateFile.decode(content);

      if (state == null) {
        Log.w('[Lifecycle] Corrupt update state file, deleting');
        await stateFile.delete();
        return;
      }

      Log.i('[Lifecycle] Stale update state: ${state.state.name}, '
          'target=${state.targetVersion}, attempt=${state.attempt}');

      switch (state.state) {
        case UpdateState.installed:
          Log.i('[Lifecycle] Update completed, cleaning up');
          await stateFile.delete();
          break;
        case UpdateState.failed:
          Log.w('[Lifecycle] Update failed: ${state.error}');
          await stateFile.delete();
          break;
        case UpdateState.installing:
        case UpdateState.restarting:
          final exeFile = InstallPaths.exeFile;
          if (exeFile.existsSync()) {
            Log.i('[Lifecycle] Update state=${state.state.name}, '
                'exe exists - assuming success');
          } else {
            Log.w('[Lifecycle] Update state=${state.state.name}, '
                'exe missing - incomplete');
          }
          await stateFile.delete();
          break;
        case UpdateState.verified:
          Log.w('[Lifecycle] Update state=verified but agent never launched, '
              'cleaning up');
          await stateFile.delete();
          break;
        default:
          Log.w('[Lifecycle] Unexpected update state=${state.state.name}, '
              'deleting');
          await stateFile.delete();
          break;
      }
    } catch (e) {
      Log.w('[Lifecycle] Stale update state recovery failed: $e');
    }
  }

  /// Run path migration if needed.
  static Future<void> runPathMigration() async {
    try {
      await PathMigration.migrateIfNeeded();
    } catch (e) {
      Log.w('[Lifecycle] Path migration failed (non-fatal): $e');
    }
  }

  /// Detect crash loop via registry guard.
  static Future<StartupLaunchGuardResult> detectCrashLoop(
      List<String> args) async {
    return await StartupService.beginLaunch(args);
  }

  /// Mark launch as completed (called after READY phase).
  static Future<void> markLaunchCompleted() async {
    await StartupService.markLaunchCompleted();
  }

  /// Mark launch as failed (called on crash/error).
  static Future<void> markLaunchFailed(String reason) async {
    await StartupService.markLaunchFailed(reason);
  }
}
