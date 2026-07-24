import 'dart:convert';
import 'dart:io';

import '../config/install_paths.dart';
import '../utils/logger.dart';

/// Migrates data from the old flat directory layout (v5.5.0 and earlier)
/// to the new separated layout (App/Data/Config/etc.).
///
/// On first launch after upgrade:
///   1. Detect old structure (no App\ subdirectory, flat files in root)
///   2. Create new subdirectories
///   3. Move files to appropriate locations
///   4. Write migration marker so it only runs once
///
/// This is a one-time operation per machine.
class PathMigration {
  PathMigration._();

  static const _markerFile = 'migration_complete.json';

  /// Check if migration is needed and perform it.
  ///
  /// Returns `true` if migration was performed, `false` if already migrated
  /// or not needed.
  static Future<bool> migrateIfNeeded() async {
    final markerFile = File('${InstallPaths.dataDir}\\$_markerFile');

    // Already migrated?
    if (markerFile.existsSync()) {
      return false;
    }

    // New structure already in use? (fresh install)
    final appSubdir = InstallPaths.appDirectory;
    if (!appSubdir.existsSync()) {
      // No App\ subdirectory — this is a pre-migration installation.
      // Migrate only if the old root directory exists.
      final rootDir = InstallPaths.rootDirectory;
      if (!rootDir.existsSync()) {
        // Fresh install — create directories, mark as migrated.
        await InstallPaths.ensureDirectories();
        await _writeMarker('fresh_install');
        return false;
      }

      // Old flat structure detected — migrate.
      Log.i('[Migration] Detected pre-migration directory structure — migrating');
      await _performMigration();
      return true;
    }

    // App\ exists but marker doesn't — write marker (shouldn't happen, but safe).
    await _writeMarker('app_dir_exists');
    return false;
  }

  static Future<void> _performMigration() async {
    try {
      await InstallPaths.ensureDirectories();

      final root = InstallPaths.rootDirectory;
      if (!root.existsSync()) return;

      // Move binaries to App\
      final executables = <String>[];
      final dlls = <String>[];

      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;

        if (name.endsWith('.exe')) {
          executables.add(name);
        } else if (name.endsWith('.dll')) {
          dlls.add(name);
        }
      }

      for (final name in executables) {
        final source = File('${InstallPaths.root}\\$name');
        final dest = File('${InstallPaths.appDir}\\$name');
        if (!dest.existsSync()) {
          await source.rename(dest.path);
          Log.d('[Migration] Moved exe: $name');
        }
      }

      for (final name in dlls) {
        final source = File('${InstallPaths.root}\\$name');
        final dest = File('${InstallPaths.appDir}\\$name');
        if (!dest.existsSync()) {
          await source.rename(dest.path);
          Log.d('[Migration] Moved dll: $name');
        }
      }

      // Move data files to Data\
      final dataFiles = {
        'update_health.json': InstallPaths.updateHealthFileInstance,
        'update_state.json': InstallPaths.updateStateFileInstance,
        'registration.json': InstallPaths.registrationFileInstance,
      };

      for (final entry in dataFiles.entries) {
        final source = File('${InstallPaths.root}\\${entry.key}');
        if (source.existsSync()) {
          if (!entry.value.existsSync()) {
            await source.rename(entry.value.path);
            Log.d('[Migration] Moved data: ${entry.key}');
          }
        }
      }

      // Move .env to Config\
      final envFile = File(InstallPaths.legacyEnvPath);
      if (envFile.existsSync()) {
        final dest = InstallPaths.envFileInstance;
        if (!dest.existsSync()) {
          await envFile.rename(dest.path);
          Log.d('[Migration] Moved .env to Config/');
        }
      }

      // Move data subdirectories (isar/, flutter_assets/) to Data\
      final dataSubdirs = ['isar'];
      for (final dirName in dataSubdirs) {
        final source = Directory('${InstallPaths.root}\\$dirName');
        if (source.existsSync()) {
          final dest = Directory('${InstallPaths.dataDir}\\$dirName');
          if (!dest.existsSync()) {
            await source.rename(dest.path);
            Log.d('[Migration] Moved directory: $dirName');
          }
        }
      }

      // Move data\ subdirectory contents if it exists at root level
      final dataDirOld = Directory('${InstallPaths.root}\\data');
      if (dataDirOld.existsSync()) {
        for (final entity in dataDirOld.listSync(followLinks: false)) {
          final name = entity.uri.pathSegments.last;
          final destPath = '${InstallPaths.appDir}\\data\\$name';
          if (!File(destPath).existsSync() && !Directory(destPath).existsSync()) {
            await entity.rename(destPath);
            Log.d('[Migration] Moved data/$name to App/data/');
          }
        }
        // Remove old data\ directory if empty
        if (dataDirOld.existsSync() &&
            dataDirOld.listSync(followLinks: false).isEmpty) {
          await dataDirOld.delete();
        }
      }

      await _writeMigrationLog();
      await _writeMarker('migrated');
      Log.i('[Migration] Complete');
    } catch (e) {
      Log.e('[Migration] Migration failed: $e');
      // Write marker anyway to prevent infinite retry loops.
      // The app will still work — some files may just be in old locations.
      await _writeMarker('partial: $e');
    }
  }

  static Future<void> _writeMarker(String status) async {
    try {
      final file = File('${InstallPaths.dataDir}\\$_markerFile');
      final data = {
        'migrated_at': DateTime.now().toIso8601String(),
        'status': status,
      };
      final tempPath = '${file.path}.tmp';
      await File(tempPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      if (file.existsSync()) await file.delete();
      await File(tempPath).rename(file.path);
    } catch (e) {
      Log.w('[Migration] Failed to write marker: $e');
    }
  }

  static Future<void> _writeMigrationLog() async {
    try {
      final logDir = InstallPaths.logDirectory;
      if (!logDir.existsSync()) {
        await logDir.create(recursive: true);
      }

      final logFile = File('${InstallPaths.logDir}\\migration.log');
      final timestamp = DateTime.now().toIso8601String();
      final logEntry = '[$timestamp] Migration completed successfully\n';
      await logFile.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      Log.w('[Migration] Failed to write migration log: $e');
    }
  }
}
