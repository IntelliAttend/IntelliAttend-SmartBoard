import 'dart:io';

import '../core/config/install_paths.dart';
import '../core/state/installation_state.dart';
import '../core/state/state_persister.dart';
import '../core/utils/logger.dart';

/// Launches the detached update agent and exits the current process.
///
/// This is the only code that launches `update_agent.exe`. The agent
/// takes ownership of `update_state.json` and handles installation,
/// verification, and app restart.
class UpdateAgentLauncher {
  UpdateAgentLauncher._();

  /// Prepare the update state file and launch the update agent.
  ///
  /// After this call, the calling process MUST exit immediately.
  /// The agent will wait for the app PID to exit, run the installer, verify
  /// the installed version, and relaunch the app.
  ///
  /// Returns `true` if the agent was launched successfully.
  static Future<bool> launch({
    required String installerPath,
    required String targetVersion,
    required String expectedSha256,
    required String logPath,
  }) async {
    try {
      // Get current process PID.
      final appPid = pid;

      // Build the state file.
      final state = UpdateStateFile(
        installerPath: installerPath,
        targetVersion: targetVersion,
        expectedSha256: expectedSha256,
        appPid: appPid,
        appExePath: InstallPaths.exePath,
        logPath: logPath,
        state: UpdateState.verified,
        createdAt: DateTime.now().toIso8601String(),
        attempt: 1,
      );

      // Persist the state file.
      await StatePersister.saveUpdateState(state);
      Log.i('[AgentLauncher] Update state written: ${state.targetVersion}');

      // Resolve the agent binary. Phase 1 isolation moved the agent OUTSIDE
      // the app install dir; boards installed before that still have it in
      // `{app}\` until their next installer run. Prefer the isolated path and
      // fall back to the legacy one so the first post-isolation update works.
      var agentFile = InstallPaths.updateAgentFile;
      if (!agentFile.existsSync()) {
        final legacy = InstallPaths.legacyUpdateAgentFile;
        if (legacy.existsSync()) {
          Log.w('[AgentLauncher] Agent not found in isolated dir '
              '(${agentFile.path}) — falling back to legacy '
              '${legacy.path}');
          agentFile = legacy;
        }
      }
      if (!agentFile.existsSync()) {
        Log.e('[AgentLauncher] Agent executable not found: ${agentFile.path}');
        return false;
      }

      // Clear any stale running marker left by a crashed agent so a fresh
      // agent boot can drop a clean marker (the installer uses it to decide
      // whether to skip overwriting the agent).
      try {
        final marker = InstallPaths.updateAgentMarkerFileInstance;
        if (marker.existsSync()) {
          await marker.delete();
          Log.i('[AgentLauncher] Removed stale agent running marker');
        }
      } catch (_) {}

      // Launch the agent with the state file path as argument.
      final process = await Process.start(
        agentFile.path,
        [InstallPaths.updateStateFile],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      Log.i('[AgentLauncher] Agent launched (${agentFile.path}), '
          'PID=${process.pid}');
      Log.i('[AgentLauncher] Exiting app (PID=$appPid) for agent takeover');

      return true;
    } catch (e) {
      Log.e('[AgentLauncher] Failed to launch agent: $e');
      return false;
    }
  }
}
