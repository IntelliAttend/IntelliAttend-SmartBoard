import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

/// Real-time Windows system metrics for the heartbeat payload.
///
/// Metrics are collected via PowerShell (same pattern as
/// [HardwareFingerprintService]) and cached for 4 minutes — slightly under the
/// 5-minute heartbeat interval — so each heartbeat reports a fresh reading
/// without running two PowerShell processes back-to-back.
///
/// Network latency is not measured here; it is fed in externally by
/// [ApiService.syncTime()] after each time-sync RTT is measured, so there are
/// no extra network calls from this service.
class SystemMetrics {
  final int memoryUsageMb;
  final double cpuLoadPercent;
  final int networkLatencyMs;

  const SystemMetrics({
    required this.memoryUsageMb,
    required this.cpuLoadPercent,
    required this.networkLatencyMs,
  });
}

class SystemMetricsService {
  static SystemMetrics? _cached;
  static DateTime? _cachedAt;
  static const Duration _cacheDuration = Duration(minutes: 4);

  /// Collects current Windows memory and CPU metrics.
  ///
  /// Returns a cached result if one is available and younger than 4 minutes.
  /// On non-Windows platforms returns all-zero metrics immediately.
  static Future<SystemMetrics> collect() async {
    final now = DateTime.now();
    if (_cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheDuration) {
      return _cached!;
    }

    if (kIsWeb || !Platform.isWindows) {
      _cached = const SystemMetrics(
        memoryUsageMb: 0,
        cpuLoadPercent: 0.0,
        networkLatencyMs: 0,
      );
      _cachedAt = now;
      return _cached!;
    }

    // Run memory and CPU queries in parallel to minimise latency.
    final results = await Future.wait([
      // Memory used = (TotalVisibleMemorySize − FreePhysicalMemory) in KB → MB
      _runPowerShell(
        r'$o=Get-CimInstance Win32_OperatingSystem; [math]::Round(($o.TotalVisibleMemorySize - $o.FreePhysicalMemory)/1024)',
      ),
      // CPU utilisation percentage (0–100)
      _runPowerShell(
        r'(Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).LoadPercentage',
      ),
    ]);

    int memoryMb = 0;
    try {
      memoryMb = int.parse(results[0] ?? '0');
    } catch (e) {
      Log.d('[Metrics] Could not parse memory value: $e');
    }

    double cpuPercent = 0.0;
    try {
      cpuPercent = double.parse(results[1] ?? '0');
    } catch (e) {
      Log.d('[Metrics] Could not parse CPU value: $e');
    }

    _cached = SystemMetrics(
      memoryUsageMb: memoryMb,
      cpuLoadPercent: cpuPercent,
      networkLatencyMs: 0,
    );
    _cachedAt = now;
    return _cached!;
  }

  static Future<String?> _runPowerShell(String command) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        return output.isNotEmpty ? output : null;
      }
    } catch (e) {
      Log.w('[Metrics] PowerShell command failed: $e');
    }
    return null;
  }
}
