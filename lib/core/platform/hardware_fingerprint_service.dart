import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
        rawString =
            'ANDROID_${Platform.localHostname}_${Platform.operatingSystemVersion}';
      } else {
        rawString = 'OTHER_${Platform.localHostname}';
      }

      final bytes = utf8.encode(rawString);
      _cachedDeviceId = sha256.convert(bytes).toString();
      return _cachedDeviceId!;
    } catch (e) {
      _cachedDeviceId =
          sha256.convert(utf8.encode(Platform.localHostname)).toString();
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

  static Future<ProcessResult?> _runSafeCommand(
      String exe, List<String> args) async {
    try {
      if (kIsWeb) return null;
      return await Process.run(exe, args);
    } catch (e) {
      Log.d('[Hardware] Command failed: $exe $args — $e');
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
    return serial ??
        await _getRegistryValue(
          r'HKLM:\HARDWARE\DESCRIPTION\System\BIOS',
          'BaseBoardSerialNumber',
        ) ??
        'UNKNOWN_MB';
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
    } catch (e) {
      Log.d('[Hardware] Could not read app version: $e');
    }

    if (kIsWeb || !Platform.isWindows) {
      _cachedMetadata = {
        'os_name': kIsWeb ? 'Web' : Platform.operatingSystem,
        'app_version': appVersion,
        'ram_gb': 0,
      };
      return _cachedMetadata!;
    }

    // Single PowerShell script to collect ALL hardware info (1 PS call instead of 18)
    final script = r'''
$mb = Get-CimInstance Win32_BaseBoard
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$disk = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
$pd = Get-PhysicalDisk | Where-Object {$_.DeviceId -eq 0} | Select-Object -First 1
$vc = Get-CimInstance Win32_VideoController | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS
$d = Get-PSDrive C
$net = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1
$wifi = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like '*Wi-Fi*' -or $_.InterfaceDescription -like '*Wireless*'} | Select-Object -First 1

@{
  motherboard_serial = $mb.SerialNumber
  cpu_id = $cpu.ProcessorId
  mac_address = ($net.MacAddress -replace '-', ':')
  os_version = $os.Caption
  brand = $cs.Manufacturer
  model = $cs.Model
  cpu_model = $cpu.Name
  cpu_cores = $cpu.NumberOfCores
  cpu_arch_code = $cpu.Architecture
  storage_total_gb = [math]::Round(($d.Used+$d.Free)/1GB,1)
  storage_free_gb = [math]::Round($d.Free/1GB,1)
  ram_total_gb = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
  ram_free_gb = [math]::Round($os.FreePhysicalMemory/1MB,1)
  storage_type = if ($pd.MediaType -match 'SSD') {'SSD'} elseif ($pd.MediaType -match 'HDD') {'HDD'} else {'Unknown'}
  screen_resolution = "$($vc.CurrentHorizontalResolution)x$($vc.CurrentVerticalResolution)"
  firmware_version = $bios.SMBIOSBIOSVersion
  network_ip = $net.IPAddress
  network_wifi_mac = $wifi.MacAddress
  disk_serial = $disk.SerialNumber
} | ConvertTo-Json -Compress
''';

    final result = await _runSafeCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);

    Map<String, dynamic> data = {};
    if (result != null && result.exitCode == 0) {
      try {
        data = jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
      } catch (e) {
        Log.d('[Hardware] Could not parse batch result: $e');
      }
    }

    int? cpuCores = data['cpu_cores'];
    String cpuArch = 'x86_64';
    final archCode = data['cpu_arch_code'];
    if (archCode == 12) {
      cpuArch = 'arm64';
    } else if (archCode == 0) {
      cpuArch = 'x86';
    }

    _cachedMetadata = {
      'motherboard_serial': data['motherboard_serial'] ?? 'UNKNOWN_MB',
      'cpu_id': data['cpu_id'] ?? 'UNKNOWN_CPU',
      'mac_address': data['mac_address'] ?? 'UNKNOWN_MAC',
      'os_name': 'Windows',
      'os_version': data['os_version'],
      'brand': data['brand'],
      'model': data['model'],
      'cpu_model': data['cpu_model'],
      'cpu_cores': cpuCores,
      'cpu_arch': cpuArch,
      'storage_total_gb': data['storage_total_gb'],
      'storage_free_gb': data['storage_free_gb'],
      'ram_total_gb': data['ram_total_gb'],
      'ram_free_gb': data['ram_free_gb'],
      'ram_gb': data['ram_total_gb'] != null
          ? (data['ram_total_gb'] as num).round()
          : 0,
      'storage_type': data['storage_type'] ?? 'Unknown',
      'screen_resolution': data['screen_resolution'],
      'firmware_version': data['firmware_version'],
      'network_ip': data['network_ip'],
      'network_wifi_mac': data['network_wifi_mac'],
      'disk_serial': data['disk_serial'],
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
        r'$m = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue; if ($null -ne $m) { $a = @{}; $a["Timeout"] = [UInt32]0; $a["Brightness"] = [Byte]' +
            original.toString() +
            r'; Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments $a -ErrorAction SilentlyContinue }',
      ]);
      if (result.exitCode == 0) {
        Log.i('💡 [Brightness] Restored to $original%.');
      } else {
        Log.w(
            '⚠️ [Brightness] Restore failed (exit ${result.exitCode}): ${result.stderr.toString().trim()}');
      }
    } catch (e) {
      Log.w('⚠️ [Brightness] Restore error: $e');
    }
  }

}
