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
  final double downloadMbps;
  final double realTimeMbps;
  final DateTime lastChecked;

  NetworkInfo({
    required this.isConnected,
    this.ssid = '',
    this.connectionType = 'None',
    this.latencyMs = 0,
    this.hasInternet = false,
    this.downloadMbps = 0,
    this.realTimeMbps = 0,
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

  String get mbpsLabel {
    if (!isConnected || downloadMbps <= 0) return '';
    if (downloadMbps >= 1) return '${downloadMbps.toStringAsFixed(1)} Mbps';
    return '${(downloadMbps * 1000).toStringAsFixed(0)} Kbps';
  }
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

  // ── Real-time throughput tracking (netstat -e delta) ──────────────────
  Timer? _throughputTimer;
  int _prevBytesReceived = 0;
  int _prevBytesSent = 0;
  DateTime? _prevThroughputTime;

  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _probe());
    _probe();
    _startThroughputMonitoring();
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _throughputTimer?.cancel();
    _throughputTimer = null;
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
      final mbps = latency > 0 ? await _measureDownloadSpeed() : 0.0;

      _update(NetworkInfo(
        isConnected: true,
        ssid: ssid,
        connectionType: connectionType,
        latencyMs: latency,
        hasInternet: latency > 0,
        downloadMbps: mbps,
        lastChecked: DateTime.now(),
      ));
    } catch (e) {
      Log.e('[NetworkInfo] Probe failed: $e');
      _update(NetworkInfo(isConnected: false, lastChecked: DateTime.now()));
    }
  }

  void _update(NetworkInfo info) {
    // Preserve real-time throughput reading when the slow probe fires.
    _current = NetworkInfo(
      isConnected: info.isConnected,
      ssid: info.ssid,
      connectionType: info.connectionType,
      latencyMs: info.latencyMs,
      hasInternet: info.hasInternet,
      downloadMbps: info.downloadMbps,
      realTimeMbps: _current.realTimeMbps,
      lastChecked: info.lastChecked,
    );
    if (!_controller.isClosed) {
      _controller.add(_current);
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

  Future<double> _measureDownloadSpeed() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final stopwatch = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse('http://speedtest.tele2.net/1MB.zip'));
      final response = await request.close().timeout(const Duration(seconds: 8));
      int bytes = 0;
      await for (final chunk in response) {
        bytes += chunk.length;
        if (stopwatch.elapsedMilliseconds > 5000) break;
      }
      await response.drain();
      client.close();
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds == 0) return 0;
      final seconds = stopwatch.elapsedMilliseconds / 1000.0;
      return (bytes * 8) / (seconds * 1000000);
    } catch (_) {
      return 0;
    }
  }

  // ── Real-time throughput via NIC byte-counter delta ────────────────────
  //
  // Reads cumulative Bytes Received / Bytes Sent from `netstat -e`
  // every 2 s and derives instantaneous throughput:
  //
  //   throughput = (Δbytes × 8) / (Δtime × 1 000 000)   →  Mbps
  //
  // This is the same MIB-II interface counter that Windows Task Manager
  // and professional network monitors (Wireshark, GlassWire) read.
  // The command itself generates zero network traffic and completes in
  // ~10 ms.

  /// Parses `netstat -e` stdout and returns `(bytesReceived, bytesSent)`.
  ///
  /// Returns `null` when the output cannot be parsed (e.g. non-English
  /// locale, unexpected format, empty string).
  static (int, int)? parseNetstatOutput(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('bytes')) {
        final numbers = RegExp(r'[\d,]+')
            .allMatches(trimmed)
            .map((m) => m.group(0)!)
            .toList();
        if (numbers.length >= 2) {
          final received = int.tryParse(numbers[0].replaceAll(',', '')) ?? 0;
          final sent = int.tryParse(numbers[1].replaceAll(',', '')) ?? 0;
          return (received, sent);
        }
        return null;
      }
    }
    return null;
  }

  /// Computes instantaneous throughput in Mbps from a byte-counter delta.
  ///
  /// [prevTotalBytes] and [currentTotalBytes] are cumulative (rx + tx).
  /// [interval] is the wall-clock time between the two readings.
  ///
  /// Returns `0.0` when the delta is non-positive or the interval is zero
  /// (guards against counter resets and clock quirks).  The result is
  /// clamped to `[0, 100_000]` Mbps.
  static double computeMbps(
    int prevTotalBytes,
    int currentTotalBytes,
    Duration interval,
  ) {
    final timeSec = interval.inMilliseconds / 1000.0;
    if (timeSec <= 0) return 0.0;
    final bytesDelta = currentTotalBytes - prevTotalBytes;
    if (bytesDelta <= 0) return 0.0;
    final mbps = (bytesDelta * 8) / (timeSec * 1000000);
    return mbps.clamp(0.0, 100000.0);
  }

  void _startThroughputMonitoring() {
    _throughputTimer?.cancel();
    _prevBytesReceived = 0;
    _prevBytesSent = 0;
    _prevThroughputTime = null;
    // Take the baseline reading immediately so the first timer tick
    // (2 s later) already has a valid delta.
    _measureThroughput();
    _throughputTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _measureThroughput(),
    );
  }

  Future<void> _measureThroughput() async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('netstat', ['-e']);
      if (result.exitCode != 0) return;

      final parsed = parseNetstatOutput(result.stdout as String);
      if (parsed == null) return;
      final (bytesReceived, bytesSent) = parsed;

      final now = DateTime.now();

      if (_prevThroughputTime != null) {
        final timeDelta = now.difference(_prevThroughputTime!);
        final totalNow = bytesReceived + bytesSent;
        final totalPrev = _prevBytesReceived + _prevBytesSent;
        final clamped = computeMbps(totalPrev, totalNow, timeDelta);

        _current = NetworkInfo(
          isConnected: _current.isConnected,
          ssid: _current.ssid,
          connectionType: _current.connectionType,
          latencyMs: _current.latencyMs,
          hasInternet: _current.hasInternet,
          downloadMbps: _current.downloadMbps,
          realTimeMbps: clamped,
          lastChecked: _current.lastChecked,
        );
        if (!_controller.isClosed) {
          _controller.add(_current);
        }
      }

      _prevBytesReceived = bytesReceived;
      _prevBytesSent = bytesSent;
      _prevThroughputTime = now;
    } catch (e) {
      Log.e('[NetworkInfo] Throughput measurement failed: $e');
    }
  }

  void dispose() {
    stopMonitoring();
    _controller.close();
  }
}
