import 'dart:convert';
import 'dart:io';

import '../config/install_paths.dart';
import '../lifecycle/app_lifecycle_manager.dart';
import '../utils/logger.dart';
import 'health_snapshot.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DiagnosticBundle
//
// Packages all diagnostic data into a single ZIP file for support.
// When a board has issues, support asks the IT admin to export a
// diagnostic bundle. The ZIP contains:
//
//   health.json         — HealthSnapshot (current state)
//   lifecycle.json      — Phase timings and completion status
//   logs/               — Recent structured log files
//   update_journal.txt  — C++ update agent transaction journal
//   recovery.json       — Recovery state (if in recovery)
//   config_summary.json — Non-sensitive config overview
//   environment.json    — OS, version, disk, process info
//
// No PII is included. JWTs, tokens, passwords, and student data are
// explicitly excluded.
// ─────────────────────────────────────────────────────────────────────────────
class DiagnosticBundle {
  DiagnosticBundle._();

  /// Create a diagnostic bundle ZIP at [outputPath].
  /// Returns the file path on success, null on failure.
  static Future<String?> create({String? outputPath}) async {
    try {
      final timestamp = DateTime.now().toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .substring(0, 19);
      final path = outputPath ??
          '${InstallPaths.logDir}\\diagnostic_bundle_$timestamp.zip';

      final tempDir = await Directory.systemTemp.createTemp('diag_bundle_');

      try {
        // 1. Health snapshot
        final health = await HealthSnapshot.capture();
        await _writeJson(tempDir, 'health.json', health.toJson());

        // 2. Lifecycle data
        await _writeJson(tempDir, 'lifecycle.json', {
          'app_version': AppLifecycleManager.appVersion,
          'completed': AppLifecycleManager.isCompleted,
          'elapsed_ms': AppLifecycleManager.elapsed.inMilliseconds,
          'timings': AppLifecycleManager.timings
              .map((t) => {
                    'phase': t.phase.name,
                    'duration_ms': t.duration.inMilliseconds,
                    'started_at': t.startedAt.toIso8601String(),
                    'completed_at': t.completedAt.toIso8601String(),
                  })
              .toList(),
        });

        // 3. Environment info
        await _writeJson(tempDir, 'environment.json', {
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'locale': Platform.localeName,
          'processors': Platform.numberOfProcessors,
          'pid': pid,
          'architecture': Platform.version,
        });

        // 4. Config summary (non-sensitive)
        await _writeJson(tempDir, 'config_summary.json', {
          'install_root': InstallPaths.root,
          'has_env_file': await File(InstallPaths.envFile).exists(),
          'has_config_file': await File(InstallPaths.configFile).exists(),
          'has_registration': await File(InstallPaths.registrationFile).exists(),
        });

        // 5. Recent log files (last 5)
        await _copyRecentLogs(tempDir);

        // 6. Update journal (if exists)
        await _copyFileIfExists(
          '${InstallPaths.root}\\update_journal.txt',
          tempDir,
          'update_journal.txt',
        );

        // 7. Recovery state (if exists)
        await _copyFileIfExists(
          '${InstallPaths.dataDir}\\recovery_state.json',
          tempDir,
          'recovery_state.json',
        );

        // Create ZIP
        await _createZip(tempDir, path);

        Log.i('[Diagnostics] Bundle created: $path');
        return path;
      } finally {
        // Clean up temp directory
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      Log.e('[Diagnostics] Failed to create bundle: $e');
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Future<void> _writeJson(
      Directory dir, String filename, Map<String, dynamic> data) async {
    final file = File('${dir.path}\\$filename');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static Future<void> _copyRecentLogs(Directory tempDir) async {
    try {
      final logDir = Directory(InstallPaths.logDir);
      if (!await logDir.exists()) return;

      final logsDir = await Directory('${tempDir.path}\\logs').create();

      final files = await logDir
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .cast<File>()
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      // Copy last 5 log files
      for (int i = 0; i < files.length && i < 5; i++) {
        final filename = files[i].path.split(Platform.pathSeparator).last;
        await files[i].copy('${logsDir.path}\\$filename');
      }
    } catch (e) {
      Log.d('[Diagnostics] Could not copy logs: $e');
    }
  }

  static Future<void> _copyFileIfExists(
      String sourcePath, Directory tempDir, String destName) async {
    try {
      final file = File(sourcePath);
      if (await file.exists()) {
        await file.copy('${tempDir.path}\\$destName');
      }
    } catch (_) {}
  }

  static Future<void> _createZip(Directory source, String outputPath) async
  {
    // Use PowerShell to create ZIP (no dart:zip dependency needed)
    final sourcePath = source.path;
    final destPath = outputPath;

    // Remove existing file if present
    final destFile = File(destPath);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    // Use Compress-Archive
    await Process.run('powershell', [
      '-Command',
      'Compress-Archive -Path "$sourcePath\\*" -DestinationPath "$destPath" -CompressionLevel Optimal',
    ]);
  }
}
