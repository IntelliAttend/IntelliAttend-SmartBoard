import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class HardwareFingerprintService {
  /// Generates a Zero-Trust Composite Hardware Fingerprint (v5.2 Alignment). 
  /// Matches the Python reference seed: motherboard_serial_cpu_id_mac_address
  static Future<String> getWindowsFingerprint() async {
    String rawString = '';

    try {
      if (kIsWeb) {
        rawString = 'WEB_BROWSER_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isWindows) {
        rawString = await _getWindowsRawV52();
      } else if (Platform.isMacOS) {
        rawString = await _getMacRaw();
      } else if (Platform.isLinux) {
        rawString = 'LINUX_${Platform.localHostname}';
      } else {
        // Fallback for mobile/other
        rawString = 'MOBILE_${Platform.localHostname}_${Platform.operatingSystemVersion}';
      }

      print('✅ [HardwareAudit] v5.2 DNA: $rawString'); 
      
      final bytes = utf8.encode(rawString);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      print('⚠️ [HardwareAudit] v5.2 Fallback: $e');
      return sha256.convert(utf8.encode(Platform.localHostname)).toString();
    }
  }

  /// v5.2 Implementation of the "Silicon Signature" (Motherboard Serial)
  static Future<String> getWindowsSiliconSignature() async {
    try {
      if (kIsWeb) return 'WEB_SILICON';
      
      String mbSerial = '';
      if (Platform.isWindows) {
        mbSerial = await _getMotherboardSerial();
      }
      return 'WIN_MB_${mbSerial.toUpperCase()}';
    } catch (e) {
      print('❌ [HardwareFingerprintService] v5.2 Silicon Extraction Failed: $e');
      return 'WIN_MB_ERROR_${Platform.localHostname.hashCode}';
    }
  }

  /// Helper to safely run OS commands without crashing on missing executables (wmic/ps)
  static Future<ProcessResult?> _runSafeCommand(String exe, List<String> args) async {
    try {
      if (kIsWeb) return null;
      return await Process.run(exe, args);
    } catch (e) {
      print('🚫 [OS_EXEC] Command Failed ($exe): $e');
      return null;
    }
  }

  static Future<String> _getMotherboardSerial() async {
    final psResult = await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance -ClassName Win32_BaseBoard).SerialNumber'
    ]);
    
    if (psResult != null && psResult.exitCode == 0) {
      final res = psResult.stdout.toString().trim();
      return res.isNotEmpty ? res : 'UNKNOWN_MB';
    }
    return 'UNKNOWN_MB';
  }

  static Future<String> _getWindowsCpuId() async {
    final psResult = await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance -ClassName Win32_Processor).ProcessorId'
    ]);
    
    if (psResult != null && psResult.exitCode == 0) {
      final res = psResult.stdout.toString().trim();
      return res.isNotEmpty ? res : 'UNKNOWN_CPU';
    }
    return 'UNKNOWN_CPU';
  }

  static Future<String> _getMacAddress() async {
    // Picking the primary IP-enabled physical MAC address
    final psResult = await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }).MACAddress | Select-Object -First 1'
    ]);
    
    if (psResult != null && psResult.exitCode == 0) {
      final res = psResult.stdout.toString().trim();
      return res.isNotEmpty ? res : 'UNKNOWN_MAC';
    }
    return 'UNKNOWN_MAC';
  }

  /// Matches the v5.2 Handshake requirements: motherboard_serial_cpu_id_mac_address
  static Future<String> _getWindowsRawV52() async {
    final mbSerial = await _getMotherboardSerial();
    final cpuId = await _getWindowsCpuId();
    final macAddr = await _getMacAddress();

    // STRICT: Seed order must match Python reference for server-side validation
    return '${mbSerial}_${cpuId}_$macAddr';
  }

  static Future<String> _getMacRaw() async {
    String uuid = '';
    // ioreg might fail in strict sandbox
    final uuidResult = await _runSafeCommand('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
    if (uuidResult != null && uuidResult.exitCode == 0) {
      final match = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch(uuidResult.stdout.toString());
      if (match != null) uuid = match.group(1) ?? '';
    }

    String serial = '';
    // system_profiler is often blocked in sandbox
    final snResult = await _runSafeCommand('bash', ['-c', "system_profiler SPHardwareDataType | awk '/Serial Number (system)/ {print \$4}'"]);
    if (snResult != null && snResult.exitCode == 0) serial = snResult.stdout.toString().trim();

    if (uuid.isEmpty && serial.isEmpty) {
      return 'MACOS_SANDBOX_${Platform.localHostname}';
    }

    return '$uuid|$serial';
  }

  /// Attempts to set the target display brightness to 100% on Windows All-In-One PCs.
  static Future<void> maximizeBrightness() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _runSafeCommand('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods).WmiSetBrightness(0, 100)'
      ]);
    } catch (e) {
      print('⚠️ [Brightness] Modern control failed: $e');
    }
  }
}
