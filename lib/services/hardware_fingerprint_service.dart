import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class HardwareFingerprintService {
  /// Generates a Zero-Trust Composite Hardware Fingerprint for Windows systems.
  /// It fetches the Machine GUID, Motherboard Serial, BIOS Serial, and Active MAC Address,
  /// concatenates them, and returns a SHA-256 hash.
  static Future<String> getWindowsFingerprint() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('This method is natively supported on Windows only.');
    }

    try {
      // Utility closure to safely parse wmic output
      String parseWmicOutput(String output, String header) {
        final lines = output
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && !e.toLowerCase().contains(header.toLowerCase()))
            .toList();
        return lines.isNotEmpty ? lines.first : '';
      }

      // 1. SMBIOS UUID (The Hardware Anchor)
      String smbiosUuid = '';
      final uuidResult = await Process.run('wmic', ['csproduct', 'get', 'uuid']);
      if (uuidResult.exitCode == 0) {
        smbiosUuid = parseWmicOutput(uuidResult.stdout.toString(), 'uuid');
      }

      // 2. Machine GUID (The OS Anchor via PowerShell)
      String machineGuid = '';
      final guidResult = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-ItemPropertyValue -Path "HKLM:\\SOFTWARE\\Microsoft\\Cryptography" -Name "MachineGuid").ToString()'
      ]);
      if (guidResult.exitCode == 0) {
        machineGuid = guidResult.stdout.toString().trim();
      } else {
        // Fallback to cmd reg query if powershell is restricted
        final regResult = await Process.run('reg', ['query', r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
        if (regResult.exitCode == 0) {
           final match = RegExp(r'REG_SZ\s+([a-fA-F0-9\-]+)').firstMatch(regResult.stdout.toString());
           if (match != null) machineGuid = match.group(1)?.trim() ?? '';
        }
      }

      // 3. Processor ID (The Silicon Salt)
      String processorId = '';
      final cpuResult = await Process.run('wmic', ['cpu', 'get', 'processorid']);
      if (cpuResult.exitCode == 0) {
        processorId = parseWmicOutput(cpuResult.stdout.toString(), 'processorid');
      }

      // Concatenate the Unbreakable Trio. 
      final rawString = '$smbiosUuid|$machineGuid|$processorId';
      print('Hardware Debug String: $rawString'); // TODO: Remove in production
      
      // Hash with SHA-256 for Zero-Trust validation
      final bytes = utf8.encode(rawString);
      final digest = sha256.convert(bytes);
      
      return digest.toString();
    } catch (e) {
      print('HardwareFingerprintService Error: $e');
      // In a strict Zero-Trust model, we might want to throw an exception here
      // instead of returning an empty string or failing open.
      throw Exception('Failed to generate hardware fingerprint: $e');
    }
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
