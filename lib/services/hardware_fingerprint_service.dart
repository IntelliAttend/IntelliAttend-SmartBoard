import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class HardwareFingerprintService {
  /// Generates a Zero-Trust Composite Hardware Fingerprint. 
  /// Supports Windows (SMBIOS/GUID/CPU) and MacOS (Hardware UUID/Serial).
  static Future<String> getWindowsFingerprint() async {
    String rawString = '';

    try {
      if (Platform.isWindows) {
        rawString = await _getWindowsRaw();
      } else if (Platform.isMacOS) {
        rawString = await _getMacRaw();
      } else {
        throw UnsupportedError('Unsupported platform for hardware fingerprinting.');
      }

      print('Hardware Debug String: $rawString'); 
      
      final bytes = utf8.encode(rawString);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      print('HardwareFingerprintService Error: $e');
      throw Exception('Failed to generate hardware fingerprint: $e');
    }
  }

  static Future<String> _getWindowsRaw() async {
    String parseWmicOutput(String output, String header) {
      final lines = output.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty && !e.toLowerCase().contains(header.toLowerCase())).toList();
      return lines.isNotEmpty ? lines.first : '';
    }

    String smbiosUuid = '';
    final uuidResult = await Process.run('wmic', ['csproduct', 'get', 'uuid']);
    if (uuidResult.exitCode == 0) smbiosUuid = parseWmicOutput(uuidResult.stdout.toString(), 'uuid');

    String machineGuid = '';
    final guidResult = await Process.run('powershell', ['-NoProfile', '-Command', '(Get-ItemPropertyValue -Path "HKLM:\\SOFTWARE\\Microsoft\\Cryptography" -Name "MachineGuid").ToString()']);
    if (guidResult.exitCode == 0) {
      machineGuid = guidResult.stdout.toString().trim();
    } else {
      final regResult = await Process.run('reg', ['query', r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
      if (regResult.exitCode == 0) {
        final match = RegExp(r'REG_SZ\s+([a-fA-F0-9\-]+)').firstMatch(regResult.stdout.toString());
        if (match != null) machineGuid = match.group(1)?.trim() ?? '';
      }
    }

    String processorId = '';
    final cpuResult = await Process.run('wmic', ['cpu', 'get', 'processorid']);
    if (cpuResult.exitCode == 0) processorId = parseWmicOutput(cpuResult.stdout.toString(), 'processorid');

    return '$smbiosUuid|$machineGuid|$processorId';
  }

  static Future<String> _getMacRaw() async {
    // 1. Hardware UUID
    String uuid = '';
    final uuidResult = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
    if (uuidResult.exitCode == 0) {
      final match = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch(uuidResult.stdout.toString());
      if (match != null) uuid = match.group(1) ?? '';
    }

    // 2. Serial Number
    String serial = '';
    final snResult = await Process.run('bash', ['-c', "system_profiler SPHardwareDataType | awk '/Serial Number (system)/ {print \$4}'"]);
    if (snResult.exitCode == 0) serial = snResult.stdout.toString().trim();

    return '$uuid|$serial';
  }


  /// Attempts to set the target display brightness to 100% on Windows All-In-One PCs.
  /// This ensures optimal conditions for scanning the dynamic QR code sprint.
  /// If the board is an External Monitor via HDMI without DDC/CI, this fails silently.
  static Future<void> maximizeBrightness() async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('wmic', [
        r'/NAMESPACE:\\root\wmi',
        'PATH',
        'WmiMonitorBrightnessMethods',
        'WHERE',
        'Active=True',
        'CALL',
        'WmiSetBrightness',
        'Brightness=100',
        'Timeout=0'
      ]);
      if (result.exitCode == 0) {
        print('Brightness maximized for QR Sprint.');
      }
    } catch (e) {
      print('Brightness control ignored/failed (likely External HDMI): $e');
    }
  }
}
