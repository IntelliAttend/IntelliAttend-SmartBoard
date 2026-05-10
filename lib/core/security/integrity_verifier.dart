import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../../firebase_options.dart';

class IntegrityVerifier {
  /// Expected SHA-256 hash injected via `--dart-define=INTEGRITY_HASH=...`
  /// at build time. Empty in dev — verification is skipped.
  static const String _expectedHash =
      String.fromEnvironment('INTEGRITY_HASH');

  static bool verify() {
    if (_expectedHash.isEmpty) return true;

    final buffer = StringBuffer();
    buffer.write(AppConfig.baseUrl);
    try {
      buffer.write(DefaultFirebaseOptions.currentPlatform.projectId);
    } catch (_) {
      if (kReleaseMode) return false;
      return true;
    }

    final computed = sha256.convert(utf8.encode(buffer.toString())).toString();
    return computed == _expectedHash;
  }

  static Future<bool> verifyCodeSignature() async {
    if (kIsWeb) return true;
    if (kDebugMode) return true;

    try {
      if (Platform.isMacOS) {
        final result =
            await Process.run('codesign', ['-v', Platform.resolvedExecutable]);
        return result.exitCode == 0;
      }
      if (Platform.isWindows) {
        final executablePath =
            Platform.resolvedExecutable.replaceAll("'", "''");
        final result = await Process.run('powershell', [
          '-NonInteractive',
          '-NoProfile',
          '-Command',
          "Get-AuthenticodeSignature -FilePath '$executablePath' | Select-Object -ExpandProperty Status",
        ]);
        return result.exitCode == 0 &&
            result.stdout.toString().trim() == 'Valid';
      }
    } catch (_) {}
    return true;
  }
}
