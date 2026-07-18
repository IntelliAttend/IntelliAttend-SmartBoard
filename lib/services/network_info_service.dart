import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/utils/logger.dart';

class NetworkInfo {
  final bool isConnected;
  final String ssid;
  final String connectionType;
  final int latencyMs;
  final bool hasInternet;
  final DateTime lastChecked;

  NetworkInfo({
    required this.isConnected,
    this.ssid = '',
    this.connectionType = 'None',
    this.latencyMs = 0,
    this.hasInternet = false,
    required this.lastChecked,
  });

  String get speedLabel {
    if (!isConnected) return 'Disconnected';
    if (!hasInternet) return 'No Internet';
    if (latencyMs < 50) return 'Excellent';
    if (latencyMs < 150) return 'Good';
    if (latencyMs < 300) return 'Slow';
    return 'Poor';
  }

  String get displaySsid {
    if (!isConnected) return 'Not connected';
    if (ssid.isEmpty) return connectionType;
    return ssid;
  }

  String get latencyLabel => '${latencyMs}ms';
}

class NetworkInfoService {
  static final NetworkInfoService _instance = NetworkInfoService._();
  factory NetworkInfoService() => _instance;
  NetworkInfoService._();

  final _controller = StreamController<NetworkInfo>.broadcast();
  Stream<NetworkInfo> get onChanged => _controller.stream;

  Timer? _pollTimer;
  NetworkInfo _current = NetworkInfo(isConnected: false, lastChecked: DateTime.now());
  NetworkInfo get current => _current;

  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _probe());
    _probe();
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _probe() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final isConnected = connectivityResults.any((r) => r != ConnectivityResult.none);

      if (!isConnected) {
        _update(NetworkInfo(isConnected: false, lastChecked: DateTime.now()));
        return;
      }

      final connectionType = _resolveType(connectivityResults);
      final ssid = await _getSsid();
      final latency = await _ping();

      _update(NetworkInfo(
        isConnected: true,
        ssid: ssid,
        connectionType: connectionType,
        latencyMs: latency,
        hasInternet: latency > 0,
        lastChecked: DateTime.now(),
      ));
    } catch (e) {
      Log.e('[NetworkInfo] Probe failed: $e');
      _update(NetworkInfo(isConnected: false, lastChecked: DateTime.now()));
    }
  }

  void _update(NetworkInfo info) {
    _current = info;
    if (!_controller.isClosed) {
      _controller.add(info);
    }
  }

  String _resolveType(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
    if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (results.contains(ConnectivityResult.mobile)) return 'Mobile';
    return 'Connected';
  }

  Future<String> _getSsid() async {
    if (!Platform.isWindows) return '';
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
      final output = result.stdout as String;
      for (final line in output.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('SSID') && !trimmed.startsWith('BSSID')) {
          final parts = trimmed.split(':');
          if (parts.length >= 2) {
            return parts.sublist(1).join(':').trim();
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<int> _ping() async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        '1.1.1.1',
        443,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  void dispose() {
    stopMonitoring();
    _controller.close();
  }
}
