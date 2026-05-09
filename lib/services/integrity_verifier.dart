import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../core/config/app_config.dart';
import '../firebase_options.dart';

class IntegrityVerifier {
  static const String _expectedHash =
      '1c3cef21dbbd2554ea605ccc971827cba2f881038eba214b3ed702f7f4825445';

  static bool verify() {
    final buffer = StringBuffer();
    buffer.write(AppConfig.baseUrl);
    try {
      buffer.write(DefaultFirebaseOptions.currentPlatform.projectId);
    } catch (_) {
      if (kReleaseMode) return false;
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
