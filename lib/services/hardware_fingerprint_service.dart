import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class HardwareFingerprintService {
  /// Returns the device_id = SHA-256(raw hardware fingerprint).
  /// This is the same value sent as the X-Device-ID header and stored
  /// in the server's smart_boards collection during OTP registration.
  /// The server uses this exact value as the HMAC key for half2 derivation.
  static Future<String> getDeviceId() async {
    String rawString = '';

    try {
      if (kIsWeb) {
        rawString = 'WEB_BROWSER_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isWindows) {
        rawString = await _getWindowsRaw();
      } else if (Platform.isAndroid) {
        rawString = 'ANDROID_${Platform.localHostname}_${Platform.operatingSystemVersion}';
      } else {
        rawString = 'OTHER_${Platform.localHostname}';
      }

      final bytes = utf8.encode(rawString);
      return sha256.convert(bytes).toString();
    } catch (e) {
      return sha256.convert(utf8.encode(Platform.localHostname)).toString();
    }
  }

  /// @Deprecated('Use getDeviceId() instead')
  static Future<String> getWindowsFingerprint() => getDeviceId();

  static Future<String> getWindowsSiliconSignature() async {
    try {
      if (kIsWeb) return 'WEB_SILICON';
      if (!Platform.isWindows) return 'NON_WINDOWS';

      String mbSerial = '';
      final psResult = await _runPowerShell(
        r'(Get-CimInstance -ClassName Win32_BaseBoard).SerialNumber',
      );
      if (psResult != null) mbSerial = psResult;

      return 'WIN_MB_${mbSerial.toUpperCase()}';
    } catch (e) {
      return 'WIN_MB_ERROR_${Platform.localHostname.hashCode}';
    }
  }

  static Future<ProcessResult?> _runSafeCommand(String exe, List<String> args) async {
    try {
      if (kIsWeb) return null;
      return await Process.run(exe, args);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _runPowerShell(String command) async {
    final result = await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);
    if (result != null && result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      return output.isNotEmpty ? output : null;
    }
    return null;
  }

  static Future<String> _getMotherboardSerial() async {
    final serial = await _runPowerShell(
      r'(Get-CimInstance -ClassName Win32_BaseBoard).SerialNumber',
    );
    return serial ?? await _getRegistryValue(
      r'HKLM:\HARDWARE\DESCRIPTION\System\BIOS',
      'BaseBoardSerialNumber',
    ) ?? 'UNKNOWN_MB';
  }

  static Future<String> _getCpuId() async {
    final cpuId = await _runPowerShell(
      r'(Get-CimInstance -ClassName Win32_Processor).ProcessorId',
    );
    return cpuId ?? 'UNKNOWN_CPU';
  }

  static Future<String> _getMacAddress() async {
    final mac = await _runPowerShell(
      r'(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true -and $_.MACAddress -ne $null }).MACAddress | Select-Object -First 1',
    );
    return mac ?? 'UNKNOWN_MAC';
  }

  static Future<String?> _getRegistryValue(String path, String name) async {
    return await _runPowerShell(
      "(Get-ItemProperty -Path '$path' -Name '$name').'$name'",
    );
  }

  /// Produces the same raw seed as the server:
  /// motherboard_serial + "_" + cpu_id + "_" + mac_address
  /// The server derives: device_id = SHA-256(seed)
  /// Both sides must use the exact same seed for HMAC keys to match.
  static Future<String> _getWindowsRaw() async {
    final results = await Future.wait([
      _getMotherboardSerial(),
      _getCpuId(),
      _getMacAddress(),
    ]);

    return results.join('_');
  }

  static Future<void> maximizeBrightness() async {
    if (kIsWeb || !Platform.isWindows) return;
    await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods).WmiSetBrightness(0, 100)',
    ]);
  }
}
