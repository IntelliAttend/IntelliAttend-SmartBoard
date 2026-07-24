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

  static const _winrtPreamble = r'''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.ApplicationModel.Package, Windows.ApplicationModel, ContentType=WindowsRuntime] | Out-Null
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

  Future<String> _runPowerShell(String script) async {
    final fullScript = '$_winrtPreamble\n$script';
    final tempFile = '${Directory.systemTemp.path}\\hotspot_cmd.ps1';
    await File(tempFile).writeAsString(fullScript, encoding: utf8);

    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', tempFile,
      ]);

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        if (stderr.isNotEmpty) {
          Log.w('[Hotspot] PowerShell stderr: $stderr');
        }
      }

      return result.stdout.toString().trim();
    } finally {
      try { await File(tempFile).delete(); } catch (_) {}
    }
  }

  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;

    // Check netsh hosted network first
    final netshEnabled = await _isEnabledNetsh();
    if (netshEnabled) return true;

    // Check WinRT system hotspot
    return _isEnabledWinRt();
  }

  Future<bool> _isEnabledNetsh() async {
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'hostednetwork']);
      return result.stdout.toString().contains('Status                  : Started');
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isEnabledWinRt() async {
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
Write-Output $mgr.TetheringOperationalState
''');
      return output == 'On';
    } catch (e) {
      return false;
    }
  }

  Future<HotspotConfig?> getConfig() async {
    if (!Platform.isWindows) return null;

    final netshConfig = await _getConfigNetsh();
    if (netshConfig != null) return netshConfig;

    return _getConfigWinRt();
  }

  Future<HotspotConfig?> _getConfigNetsh() async {
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'hostednetwork']);
      final output = result.stdout.toString();

      String ssid = '';
      String password = '';
      String status = 'Stopped';

      for (final line in output.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('SSID name')) {
          ssid = trimmed.split(':').last.trim();
        }
        if (trimmed.startsWith('Key content')) {
          password = trimmed.split(':').last.trim();
        }
        if (trimmed.startsWith('Status')) {
          status = trimmed.split(':').last.trim();
        }
      }

      if (ssid.isNotEmpty) {
        return HotspotConfig(ssid: ssid, password: password, isRunning: status == 'Started');
      }
    } catch (e) {
      Log.w('[Hotspot] netsh config failed: $e');
    }
    return null;
  }

  Future<HotspotConfig?> _getConfigWinRt() async {
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
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
      Log.w('[Hotspot] WinRT config failed: $e');
    }
    return null;
  }

  Future<List<Map<String, String>>> getConnectedClients() async {
    if (!Platform.isWindows) return [];

    final netshClients = await _getClientsNetsh();
    if (netshClients.isNotEmpty) return netshClients;

    return _getClientsWinRt();
  }

  Future<List<Map<String, String>>> _getClientsWinRt() async {
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
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
      Log.w('[Hotspot] WinRT clients failed: $e');
    }
    return [];
  }

  Future<List<Map<String, String>>> _getClientsNetsh() async {
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'hostednetwork']);
      final output = result.stdout.toString();
      final clients = <Map<String, String>>[];

      final lines = output.split('\n');
      var inClientSection = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.contains('Number of clients')) {
          inClientSection = true;
          continue;
        }
        if (inClientSection && trimmed.contains(':')) {
          final parts = trimmed.split(':').map((s) => s.trim()).toList();
          if (parts.length >= 2 && parts[0].isNotEmpty) {
            clients.add({'identifier': parts[0], 'value': parts[1]});
          }
        }
      }
      return clients;
    } catch (e) {
      return [];
    }
  }

  /// Starts the hotspot with the given SSID and password.
  /// 1. Tries WinRT with ConfigureAccessPointAsync (sets custom SSID/password, then starts)
  /// 2. Falls back to netsh hosted network (legacy, custom SSID/password)
  /// 3. Falls back to WinRT StartTetheringAsync (system default config)
  Future<bool> start({required String ssid, required String password}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Hotspot is only supported on Windows');
    }

    Log.i('[Hotspot] Starting hotspot: $ssid');

    // Strategy 1: WinRT with ConfigureAccessPointAsync (sets custom SSID/password)
    try {
      final result = await _startWinRtConfigured(ssid: ssid, password: password);
      Log.i('[Hotspot] WinRT configured start succeeded');
      return result;
    } catch (e) {
      Log.w('[Hotspot] WinRT configured start failed: $e');
    }

    // Strategy 2: netsh hosted network (legacy, custom SSID/password)
    try {
      await _startNetsh(ssid: ssid, password: password);
      Log.i('[Hotspot] netsh start succeeded');
      return true;
    } catch (e) {
      Log.w('[Hotspot] netsh start failed: $e');
    }

    // Strategy 3: WinRT StartTetheringAsync (system default config)
    try {
      await _startWinRtDefault();
      Log.i('[Hotspot] WinRT default start succeeded');
      return true;
    } catch (e) {
      if (e is HotspotException) rethrow;
      throw HotspotException('Failed to start hotspot: $e');
    }
  }

  /// WinRT: Configure custom SSID/password, then start
  Future<bool> _startWinRtConfigured({required String ssid, required String password}) async {
    // Use single-quote escaping (safest PowerShell context) for user values.
    final safeSsid = PowerShellEscape.singleQuote(ssid);
    final safePass = PowerShellEscape.singleQuote(password);

    final output = await _runPowerShell('''
\$config = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration]::new()
\$config.Ssid = '$safeSsid'
\$config.Passphrase = '$safePass'

\$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
\$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile(\$cp)

Write-Output "Configuring..."
\$task = \$mgr.ConfigureAccessPointAsync(\$config)
\$task.Wait()

Write-Output "Starting..."
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

  /// WinRT: Start with system default config
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

  /// netsh: Legacy hosted network with custom SSID/password
  Future<void> _startNetsh({required String ssid, required String password}) async {
    // Validate SSID/password before passing to netsh.
    final safeSsid = PowerShellEscape.forNetsh(ssid, field: 'SSID');
    final safePassword = PowerShellEscape.forNetsh(password, field: 'Password');
    final configResult = await Process.run('netsh', [
      'wlan', 'set', 'hostednetwork', 'mode=allow',
      'ssid=$safeSsid', 'key=$safePassword',
    ]);
    Log.i('[Hotspot] netsh config: ${configResult.stdout}');

    if (_isAdminError(configResult.stdout.toString(), configResult.stderr.toString())) {
      throw HotspotException('Administrator privileges required');
    }

    final output = configResult.stdout.toString().toLowerCase();
    if (output.contains('not supported') || output.contains('cannot be set')) {
      throw HotspotException('Hosted network not supported');
    }

    final startResult = await Process.run('netsh', ['wlan', 'start', 'hostednetwork']);
    Log.i('[Hotspot] netsh start: ${startResult.stdout}');

    if (_isAdminError(startResult.stdout.toString(), startResult.stderr.toString())) {
      throw HotspotException('Administrator privileges required');
    }

    final startOutput = startResult.stdout.toString();
    if (startOutput.toLowerCase().contains('not supported')) {
      throw HotspotException('Hosted network not supported');
    }
    if (!startOutput.contains('started') && !startOutput.contains('Started')) {
      throw HotspotException('netsh start failed: $startOutput');
    }
  }

  /// Stops the hotspot (both netsh and WinRT).
  Future<bool> stop() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Hotspot is only supported on Windows');
    }

    Log.i('[Hotspot] Stopping hotspot');
    var anyStopped = false;

    // Stop netsh hosted network
    try {
      final result = await Process.run('netsh', ['wlan', 'stop', 'hostednetwork']);
      Log.i('[Hotspot] netsh stop: ${result.stdout}');
      anyStopped = true;
    } catch (e) {
      Log.w('[Hotspot] netsh stop failed: $e');
    }

    // Stop WinRT system hotspot
    try {
      final output = await _runPowerShell(r'''
$cp = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($cp)
$opResult = AwaitOp $mgr.StopTetheringAsync() ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime])
Write-Output $opResult.Status
''');
      Log.i('[Hotspot] WinRT stop: $output');
      anyStopped = true;
    } catch (e) {
      Log.w('[Hotspot] WinRT stop failed: $e');
    }

    return anyStopped;
  }

  bool _isAdminError(String stdout, String stderr) {
    return stdout.toLowerCase().contains('admin privilege') ||
        stderr.toLowerCase().contains('admin privilege');
  }
}

class HotspotException implements Exception {
  final String message;
  const HotspotException(this.message);

  bool get isAdminRequired => message.toLowerCase().contains('administrator');

  @override
  String toString() => message;
}
