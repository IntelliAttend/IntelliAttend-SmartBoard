import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/logger.dart';

class HardwareFingerprintService {
  // Cached on first call — avoids re-running 3 PowerShell processes on every
  // API request. The hardware fingerprint never changes within a single run.
  static String? _cachedDeviceId;

  // Cached hardware metadata — pre-warmed while the OTP screen is showing so
  // completeRegistration() returns the map instantly without waiting for 18
  // parallel PowerShell queries at the critical post-OTP moment.
  static Map<String, dynamic>? _cachedMetadata;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
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
      _cachedDeviceId = sha256.convert(bytes).toString();
      return _cachedDeviceId!;
    } catch (e) {
      _cachedDeviceId = sha256.convert(utf8.encode(Platform.localHostname)).toString();
      return _cachedDeviceId!;
    }
  }

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

  static Future<String> _getWindowsRaw() async {
    final results = await Future.wait([
      _getMotherboardSerial(),
      _getCpuId(),
      _getMacAddress(),
    ]);

    return results.join('_');
  }

  static Future<Map<String, dynamic>> getHardwareMetadata() async {
    // Return cached result immediately — the cache is pre-warmed during the
    // OTP entry screen so this path is instant at the critical bond moment.
    if (_cachedMetadata != null) return _cachedMetadata!;

    String? appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    if (kIsWeb || !Platform.isWindows) {
      _cachedMetadata = {
        'os_name': kIsWeb ? 'Web' : Platform.operatingSystem,
        'app_version': appVersion,
        'ram_gb': 0,
      };
      return _cachedMetadata!;
    }

    // Run independent queries in parallel
    final results = await Future.wait([
      _getMotherboardSerial(),                          // 0
      _getCpuId(),                                      // 1
      _getMacAddress(),                                 // 2
      _runPowerShell(r'(Get-CimInstance Win32_OperatingSystem).Caption'),  // 3 os_version
      _runPowerShell(r'(Get-CimInstance Win32_ComputerSystem).Manufacturer'), // 4 brand
      _runPowerShell(r'(Get-CimInstance Win32_ComputerSystem).Model'),     // 5 model
      _runPowerShell(r'(Get-CimInstance Win32_Processor | Select-Object -First 1).Name'), // 6 cpu_model
      _runPowerShell(r'(Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfCores'), // 7 cpu_cores
      _runPowerShell(r'(Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture'), // 8 cpu_arch_code
      _runPowerShell(r'$d=Get-PSDrive C; "$([math]::Round(($d.Used+$d.Free)/1GB,1)),$([math]::Round($d.Free/1GB,1))"'), // 9 storage
      _runPowerShell(r'$o=Get-CimInstance Win32_OperatingSystem; "$([math]::Round($o.TotalVisibleMemorySize/1MB,1)),$([math]::Round($o.FreePhysicalMemory/1MB,1))"'), // 10 ram
      _runPowerShell(r'(Get-PhysicalDisk | Where-Object {$_.DeviceId -eq 0}).MediaType'), // 11 storage_type
      _runPowerShell(r'$v=Get-CimInstance Win32_VideoController|Select-Object -First 1; "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution)"'), // 12 screen_resolution
      _runPowerShell(r'(Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion'), // 13 firmware_version
      _runPowerShell(r"(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress"), // 14 network_ip
      _runPowerShell(r"(Get-NetAdapter | Where-Object {$_.InterfaceDescription -like '*Wi-Fi*' -or $_.InterfaceDescription -like '*Wireless*'} | Select-Object -First 1).MacAddress"), // 15 network_wifi_mac
      _runPowerShell(r'(Get-CimInstance Win32_DiskDrive | Select-Object -First 1).SerialNumber'), // 16 disk_serial
      _runPowerShell(r"(Get-PnpDevice -Class 'HIDClass' | Where-Object {$_.FriendlyName -like '*touch*'}).Count -gt 0"), // 17 touch_capable
    ]);

    // cpu_cores
    int? cpuCores;
    try { cpuCores = int.parse(results[7] ?? ''); } catch (_) {}

    // cpu_arch
    String cpuArch = 'x86_64';
    try {
      final archCode = int.parse(results[8] ?? '');
      if (archCode == 12) {
        cpuArch = 'arm64';
      } else if (archCode == 0) {
        cpuArch = 'x86';
      } else {
        cpuArch = 'x86_64';
      }
    } catch (_) {}

    // storage
    double? storageTotalGb, storageFreeGb;
    try {
      final parts = (results[9] ?? '').split(',');
      if (parts.length == 2) {
        storageTotalGb = double.parse(parts[0].trim());
        storageFreeGb = double.parse(parts[1].trim());
      }
    } catch (_) {}

    // ram
    double? ramTotalGb, ramFreeGb;
    try {
      final parts = (results[10] ?? '').split(',');
      if (parts.length == 2) {
        ramTotalGb = double.parse(parts[0].trim());
        ramFreeGb = double.parse(parts[1].trim());
      }
    } catch (_) {}

    // storage_type
    String storageType = 'Unknown';
    final mediaType = results[11] ?? '';
    if (mediaType.contains('SSD')) {
      storageType = 'SSD';
    } else if (mediaType.contains('HDD')) {
      storageType = 'HDD';
    }

    // touch_capable
    bool? touchCapable;
    final touchRaw = (results[17] ?? '').toLowerCase();
    if (touchRaw == 'true') {
      touchCapable = true;
    } else if (touchRaw == 'false') {
      touchCapable = false;
    }

    _cachedMetadata = {
      'motherboard_serial': results[0],
      'cpu_id': results[1],
      'mac_address': results[2],
      'os_name': 'Windows',
      'os_version': results[3],
      'brand': results[4],
      'model': results[5],
      'cpu_model': results[6],
      'cpu_cores': cpuCores,
      'cpu_arch': cpuArch,
      'storage_total_gb': storageTotalGb,
      'storage_free_gb': storageFreeGb,
      'ram_total_gb': ramTotalGb,
      'ram_free_gb': ramFreeGb,
      // Contract v1.1: ram_gb (integer, Required) — total RAM rounded to nearest GB.
      'ram_gb': ramTotalGb != null ? ramTotalGb.round() : 0,
      'storage_type': storageType,
      'screen_resolution': results[12],
      'firmware_version': results[13],
      'network_ip': results[14],
      'network_wifi_mac': results[15],
      'disk_serial': results[16],
      'touch_capable': touchCapable,
      'app_version': appVersion,
      'screen_size_inch': null,
    };
    return _cachedMetadata!;
  }

  /// Saved original brightness level (0-100) so it can be restored after
  /// the attendance session ends.
  static int? _originalBrightness;

  /// Reads the current monitor brightness via WMI (0-100).
  static Future<int?> getCurrentBrightness() async {
    if (kIsWeb || !Platform.isWindows) return null;
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness).CurrentBrightness',
    ]);
    if (result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      final parsed = int.tryParse(output);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Saves the current brightness level and then sets the display to 100%.
  /// Subsequent calls without an intervening [restoreBrightness] are no-ops
  /// so the original value is never overwritten.
  static Future<void> maximizeBrightness() async {
    if (kIsWeb || !Platform.isWindows) return;
    // Only save once — the original brightness must survive across re-entries.
    if (_originalBrightness == null) {
      _originalBrightness = await getCurrentBrightness();
      Log.i('💡 [Brightness] Saved original brightness: $_originalBrightness');
    }
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'$m = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue; if ($null -ne $m) { $a = @{}; $a["Timeout"] = [UInt32]0; $a["Brightness"] = [Byte]100; Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments $a -ErrorAction Stop; exit 0 } else { Write-Error "No WmiMonitorBrightnessMethods instances found"; exit 1 }',
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'maximizeBrightness failed (exit ${result.exitCode}): ${result.stderr.toString().trim()}',
      );
    }
    Log.i('💡 [Brightness] Display set to 100%.');
  }

  /// Restores the display brightness to the value saved by [maximizeBrightness].
  /// Once restored, the saved value is cleared so a future call to
  /// [maximizeBrightness] will re-save.
  static Future<void> restoreBrightness() async {
    if (kIsWeb || !Platform.isWindows) return;
    final original = _originalBrightness;
    if (original == null) return;
    _originalBrightness = null; // Clear so next maximize re-saves
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$m = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue; if ($null -ne $m) { $a = @{}; $a["Timeout"] = [UInt32]0; $a["Brightness"] = [Byte]' + original.toString() + r'; Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments $a -ErrorAction SilentlyContinue }',
      ]);
      if (result.exitCode == 0) {
        Log.i('💡 [Brightness] Restored to $original%.');
      } else {
        Log.w('⚠️ [Brightness] Restore failed (exit ${result.exitCode}): ${result.stderr.toString().trim()}');
      }
    } catch (e) {
      Log.w('⚠️ [Brightness] Restore error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Screen capture prevention (Windows only)
  //
  // Uses SetWindowDisplayAffinity via Win32 FFI to block screenshots, screen
  // recording, and screen sharing of the HWND. WDA_MONITOR makes captured
  // content appear black/blank.
  // ---------------------------------------------------------------------------

  static const int _wdaNone = 0x00000000;
  static const int _wdaMonitor = 0x00000001;

  static DynamicLibrary? _user32;
  static int Function(int, int)? _setWindowDisplayAffinity;

  static void _ensureScreenCaptureApi() {
    if (_user32 != null) return;
    if (kIsWeb || !Platform.isWindows) return;
    _user32 = DynamicLibrary.open('user32.dll');
    _setWindowDisplayAffinity = _user32!
        .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'SetWindowDisplayAffinity',
    );
  }

  /// Prevents the window from being captured in screenshots, recordings, and
  /// screen sharing. Captured content will appear black/blank.
  static Future<void> preventScreenCapture() async {
    if (kIsWeb || !Platform.isWindows) return;
    _ensureScreenCaptureApi();
    final hwnd = await windowManager.getId();
    final result = _setWindowDisplayAffinity!(hwnd, _wdaMonitor);
    if (result == 0) {
      throw Exception('SetWindowDisplayAffinity(WDA_MONITOR) failed');
    }
  }

  /// Restores normal screen capture behavior for the window.
  static Future<void> allowScreenCapture() async {
    if (kIsWeb || !Platform.isWindows) return;
    _ensureScreenCaptureApi();
    final hwnd = await windowManager.getId();
    final result = _setWindowDisplayAffinity!(hwnd, _wdaNone);
    if (result == 0) {
      throw Exception('SetWindowDisplayAffinity(WDA_NONE) failed');
    }
  }
}
