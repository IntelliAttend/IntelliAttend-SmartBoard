import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/utils/logger.dart';
import '../core/utils/powershell_escape.dart';

class HotspotConfig {
  final String ssid;
  final String password;
  final String band;
  final bool isRunning;

  const HotspotConfig({
    required this.ssid,
    required this.password,
    this.band = 'Auto',
    this.isRunning = false,
  });
}

class HotspotService {
  HotspotService._();
  static final HotspotService _instance = HotspotService._();
  factory HotspotService() => _instance;

  // WinRT type loading preamble — loaded once per PowerShell session.
  // Simplified: only loads what's needed, no reflection for async.
  static const _winrtPreamble = r'''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime] | Out-Null
[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime] | Out-Null
[Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime] | Out-Null
$asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function AwaitOp($task, $type) {
    $m = $asTaskOp.MakeGenericMethod($type)
    $t = $m.Invoke($null, @($task))
    $t.Wait(-1) | Out-Null
    $t.Result
}
''';

  /// Runs a PowerShell script inline (no temp file).
  Future<String> _runPowerShell(String script) async {
    final fullScript = '$_winrtPreamble\n$script';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      fullScript,
    ]);

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      if (stderr.isNotEmpty) {
        Log.w('[Hotspot] PowerShell stderr: $stderr');
      }
    }

    return result.stdout.toString().trim();
  }

  /// Checks if the device supports WinRT tethering.
  Future<bool> isSupported() async {
    if (!Platform.isWindows) return false;
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $cp) { Write-Output "False"; exit }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
Write-Output $mgr.IsTetheringSupported
''');
      return output.trim() == 'True';
    } catch (e) {
      Log.w('[Hotspot] Support check failed: $e');
      return false;
    }
  }

  /// Checks if the hotspot is currently running.
  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $cp) { Write-Output "Unknown"; exit }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
Write-Output $mgr.TetheringOperationalState
''');
      return output.trim() == 'On';
    } catch (e) {
      return false;
    }
  }

  /// Gets the current hotspot configuration.
  Future<HotspotConfig?> getConfig() async {
    if (!Platform.isWindows) return null;
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $cp) { exit }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
$config = $mgr.GetCurrentAccessPointConfiguration()
$state = $mgr.TetheringOperationalState
@{Ssid=$config.Ssid; Password=$config.Passphrase; Band="Auto"; IsRunning=($state -eq "On")} | ConvertTo-Json -Compress
''');

      if (output.isNotEmpty && output.contains('{')) {
        final map = jsonDecode(output) as Map<String, dynamic>;
        return HotspotConfig(
          ssid: (map['Ssid'] ?? '').toString(),
          password: (map['Password'] ?? '').toString(),
          band: (map['Band'] ?? 'Auto').toString(),
          isRunning: map['IsRunning'] == true,
        );
      }
    } catch (e) {
      Log.w('[Hotspot] getConfig failed: $e');
    }
    return null;
  }

  /// Gets connected clients.
  Future<List<Map<String, String>>> getConnectedClients() async {
    if (!Platform.isWindows) return [];
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $cp) { exit }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
$clients = AwaitOp $mgr.GetTetheringClients() ([System.Collections.Generic.IReadOnlyList`1[Windows.Networking.NetworkOperators.TetheringClient], System.Collections.Generic.IReadOnlyList`1, ContentType=WindowsRuntime])
$jsonArr = @()
foreach ($c in $clients) {
    $jsonArr += @{MacAddress="$($c.MacAddress.Address)"; HostName="$($c.HostName)"; IsCurrentlyConnected=$c.IsCurrentlyConnected}
}
$jsonArr | ConvertTo-Json -Compress
''');

      if (output.isNotEmpty && output.contains('{')) {
        final parsed = jsonDecode(output);
        if (parsed is List) {
          return parsed.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))).toList();
        } else if (parsed is Map) {
          return [parsed.map((k, v) => MapEntry(k.toString(), v.toString()))];
        }
      }
    } catch (e) {
      Log.w('[Hotspot] getConnectedClients failed: $e');
    }
    return [];
  }

  /// Starts the hotspot with the given SSID and password.
  /// Uses WinRT ConfigureAccessPointAsync (sets custom SSID/password, then starts).
  Future<bool> start({required String ssid, required String password}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Hotspot is only supported on Windows');
    }

    // Check support first
    if (!await isSupported()) {
      throw HotspotException('Hotspot is not supported on this device');
    }

    Log.i('[Hotspot] Starting hotspot: $ssid');

    try {
      final result = await _startWinRtConfigured(ssid: ssid, password: password);
      Log.i('[Hotspot] WinRT configured start succeeded');
      return result;
    } catch (e) {
      Log.w('[Hotspot] WinRT configured start failed: $e');
    }

    // Fallback: WinRT StartTetheringAsync (system default config)
    try {
      await _startWinRtDefault();
      Log.i('[Hotspot] WinRT default start succeeded');
      return true;
    } catch (e) {
      if (e is HotspotException) rethrow;
      throw HotspotException('Failed to start hotspot: $e');
    }
  }

  /// WinRT: Configure custom SSID/password, then start.
  Future<bool> _startWinRtConfigured({required String ssid, required String password}) async {
    final safeSsid = PowerShellEscape.singleQuote(ssid);
    final safePass = PowerShellEscape.singleQuote(password);

    final output = await _runPowerShell('''
\$config = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration]::new()
\$config.Ssid = '$safeSsid'
\$config.Passphrase = '$safePass'

\$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
\$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile(\$cp)

\$task = \$mgr.ConfigureAccessPointAsync(\$config)
\$task.Wait()

\$result = AwaitOp \$mgr.StartTetheringAsync() ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime])
Write-Output "Result:\$(\$result.Status)"
''');
    Log.i('[Hotspot] WinRT configured: $output');

    if (output.contains('Result:Success') || output.contains('InProgress')) {
      return true;
    }

    if (output.contains('InternetSharingSourceNotConnected')) {
      throw HotspotException('No internet connection available for sharing');
    }
    if (output.contains('RadioNotAvailable')) {
      throw HotspotException('Wi-Fi radio is not available');
    }

    throw HotspotException('WinRT configure failed: $output');
  }

  /// WinRT: Start with system default config.
  Future<void> _startWinRtDefault() async {
    final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
$opResult = AwaitOp $mgr.StartTetheringAsync() ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime])
Write-Output $opResult.Status
''');
    Log.i('[Hotspot] WinRT default: $output');

    if (output.contains('Success') || output == 'InProgress') return;

    if (output.contains('InternetSharingSourceNotConnected')) {
      throw HotspotException('No internet connection available for sharing');
    }
    if (output.contains('RadioNotAvailable')) {
      throw HotspotException('Wi-Fi radio is not available');
    }
    if (output.contains('TetheringOperationAlreadyInProgress')) return;

    throw HotspotException('WinRT start failed: $output');
  }

  /// Stops the hotspot.
  Future<bool> stop() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Hotspot is only supported on Windows');
    }

    Log.i('[Hotspot] Stopping hotspot');
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $cp) { Write-Output "NoConnection"; exit }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
$opResult = AwaitOp $mgr.StopTetheringAsync() ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime])
Write-Output $opResult.Status
''');
      Log.i('[Hotspot] WinRT stop: $output');
      return true;
    } catch (e) {
      Log.w('[Hotspot] stop failed: $e');
      return false;
    }
  }
}

class HotspotException implements Exception {
  final String message;
  const HotspotException(this.message);

  bool get isAdminRequired => message.toLowerCase().contains('administrator');

  @override
  String toString() => message;
}
