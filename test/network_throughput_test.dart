import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/network_info_service.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════
  //  NetworkInfo model
  // ════════════════════════════════════════════════════════════════════════
  group('NetworkInfo model', () {
    test('realTimeMbps defaults to 0', () {
      final info = NetworkInfo(isConnected: true, lastChecked: DateTime.now());
      expect(info.realTimeMbps, 0.0);
    });

    test('realTimeMbps can be set explicitly', () {
      final info = NetworkInfo(
        isConnected: true,
        realTimeMbps: 42.7,
        lastChecked: DateTime.now(),
      );
      expect(info.realTimeMbps, 42.7);
    });

    test('downloadMbps is unaffected by realTimeMbps', () {
      final info = NetworkInfo(
        isConnected: true,
        downloadMbps: 15.3,
        realTimeMbps: 8.1,
        lastChecked: DateTime.now(),
      );
      expect(info.downloadMbps, 15.3);
      expect(info.realTimeMbps, 8.1);
    });

    test('mbpsLabel still uses downloadMbps', () {
      final info = NetworkInfo(
        isConnected: true,
        downloadMbps: 25.0,
        realTimeMbps: 99.0,
        lastChecked: DateTime.now(),
      );
      expect(info.mbpsLabel, '25.0 Mbps');
    });

    test('all fields carry through correctly', () {
      final info = NetworkInfo(
        isConnected: true,
        ssid: 'TestNetwork',
        connectionType: 'WiFi',
        latencyMs: 30,
        hasInternet: true,
        downloadMbps: 50.0,
        realTimeMbps: 12.3,
        lastChecked: DateTime(2026, 7, 19),
      );
      expect(info.isConnected, true);
      expect(info.ssid, 'TestNetwork');
      expect(info.connectionType, 'WiFi');
      expect(info.latencyMs, 30);
      expect(info.hasInternet, true);
      expect(info.downloadMbps, 50.0);
      expect(info.realTimeMbps, 12.3);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  //  parseNetstatOutput — parsing accuracy
  // ════════════════════════════════════════════════════════════════════════
  group('parseNetstatOutput', () {
    test('parses standard Windows netstat -e output', () {
      const output = '''
Interface Statistics

                                Received             Sent

Bytes                          2345678901         1234567890
Unicast packets                  2345678            1234567
Non-unicast packets                 12345              67890
Discards                               0                  0
Errors                                 0                  0
Unknown protocols                       0
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 2345678901); // received
      expect(result.$2, 1234567890); // sent
    });

    test('parses output with CRLF line endings', () {
      const output =
          'Interface Statistics\r\n'
          '\r\n'
          '                                Received             Sent\r\n'
          '\r\n'
          'Bytes                          100000000           50000000\r\n'
          'Unicast packets                   100000             50000\r\n';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 100000000);
      expect(result.$2, 50000000);
    });

    test('parses output with comma-separated values (some locales)', () {
      const output = '''
Interface Statistics

Bytes                  1,234,567,890        987,654,321
Unicast packets            1,234,567            987,654
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 1234567890);
      expect(result.$2, 987654321);
    });

    test('parses zero bytes (fresh boot)', () {
      const output = '''
Interface Statistics

                                Received             Sent

Bytes                                    0                  0
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 0);
      expect(result.$2, 0);
    });

    test('parses very large byte values (multi-GB session)', () {
      const output = '''
Interface Statistics

Bytes                        1099511627776     549755813888
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 1099511627776); // ~1 TB received
      expect(result.$2, 549755813888); // ~512 GB sent
    });

    test('returns null for empty string', () {
      final result = NetworkInfoService.parseNetstatOutput('');
      expect(result, isNull);
    });

    test('returns null when Bytes line has no numbers', () {
      const output = '''
Interface Statistics

Bytes                          abc              def
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNull);
    });

    test('returns null when no Bytes line exists', () {
      const output = '''
Interface Statistics

Received             Sent
Unicast packets       12345
Non-unicast packets    6789
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNull);
    });

    test('handles Bytes line with extra whitespace', () {
      const output = '''
Bytes                              5000000           3000000
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 5000000);
      expect(result.$2, 3000000);
    });

    test('case-insensitive Bytes prefix', () {
      const output = 'bytes                          1000000           500000\n';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 1000000);
      expect(result.$2, 500000);
    });

    test('only first Bytes line is used', () {
      const output = '''
Bytes                          1111111           2222222
Bytes                          9999999           8888888
''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 1111111);
      expect(result.$2, 2222222);
    });

    test('handles output with leading/trailing newlines', () {
      const output = '''

Bytes                          4200000           1300000

''';
      final result = NetworkInfoService.parseNetstatOutput(output);
      expect(result, isNotNull);
      expect(result!.$1, 4200000);
      expect(result.$2, 1300000);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  //  computeMbps — calculation accuracy
  // ════════════════════════════════════════════════════════════════════════
  group('computeMbps', () {
    test('computes 1 Mbps for 1,250,000 bytes over 10 seconds', () {
      // 1,250,000 bytes × 8 bits / 10 s / 1,000,000 = 1.0 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        1250000,
        const Duration(seconds: 10),
      );
      expect(mbps, closeTo(1.0, 0.001));
    });

    test('computes 10 Mbps for 2,500,000 bytes over 2 seconds', () {
      // 2,500,000 × 8 / 2 / 1,000,000 = 10.0 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        2500000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(10.0, 0.001));
    });

    test('computes 100 Mbps for 25,000,000 bytes over 2 seconds', () {
      final mbps = NetworkInfoService.computeMbps(
        0,
        25000000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(100.0, 0.001));
    });

    test('computes 1 Gbps (1000 Mbps) correctly', () {
      // 250,000,000 bytes × 8 / 2 s / 1,000,000 = 1000 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        250000000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(1000.0, 0.01));
    });

    test('computes 0.5 Mbps for small transfer', () {
      // 125,000 bytes × 8 / 2 / 1,000,000 = 0.5 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        125000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(0.5, 0.001));
    });

    test('computes delta between two non-zero readings', () {
      // prev = 1,000,000 bytes total, now = 3,500,000 bytes total
      // delta = 2,500,000 bytes, over 2 s = 10.0 Mbps
      final mbps = NetworkInfoService.computeMbps(
        1000000,
        3500000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(10.0, 0.001));
    });

    test('returns 0.0 when delta is zero (no traffic)', () {
      final mbps = NetworkInfoService.computeMbps(
        5000000,
        5000000,
        const Duration(seconds: 2),
      );
      expect(mbps, 0.0);
    });

    test('returns 0.0 when delta is negative (counter reset)', () {
      final mbps = NetworkInfoService.computeMbps(
        999999999,
        1000000,
        const Duration(seconds: 2),
      );
      expect(mbps, 0.0);
    });

    test('returns 0.0 when interval is zero', () {
      final mbps = NetworkInfoService.computeMbps(
        0,
        5000000,
        Duration.zero,
      );
      expect(mbps, 0.0);
    });

    test('clamps to 100,000 Mbps (upper bound)', () {
      // Absurdly large delta to exceed the clamp
      final mbps = NetworkInfoService.computeMbps(
        0,
        1000000000000, // 1 TB
        const Duration(milliseconds: 1), // 1 ms
      );
      expect(mbps, 100000.0);
    });

    test('handles millisecond-level precision', () {
      // 125,000 bytes over 1 ms = 1000 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        125000,
        const Duration(milliseconds: 1),
      );
      expect(mbps, closeTo(1000.0, 0.1));
    });

    test('handles sub-second intervals', () {
      // 625,000 bytes over 500 ms = 10 Mbps
      final mbps = NetworkInfoService.computeMbps(
        0,
        625000,
        const Duration(milliseconds: 500),
      );
      expect(mbps, closeTo(10.0, 0.01));
    });

    test('negative interval returns 0.0', () {
      final mbps = NetworkInfoService.computeMbps(
        0,
        5000000,
        const Duration(seconds: -1),
      );
      expect(mbps, 0.0);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  //  Simulation — multi-step throughput pipeline
  // ════════════════════════════════════════════════════════════════════════
  group('Throughput simulation', () {
    test('simulates 5 consecutive readings with steady traffic', () {
      // Simulate a NIC that receives 1 MB/s and sends 0.5 MB/s = 1.5 MB/s
      // total = 12 Mbps over 2-second intervals.
      const bytesPerSec = 1500000; // 1.5 MB/s = 12 Mbps
      const interval = Duration(seconds: 2);

      var totalBytes = 10000000; // Starting cumulative value
      double? previousMpbs;

      for (var i = 0; i < 5; i++) {
        final prevTotal = totalBytes;
        totalBytes += bytesPerSec * interval.inSeconds;
        final mbps = NetworkInfoService.computeMbps(prevTotal, totalBytes, interval);

        expect(mbps, closeTo(12.0, 0.01),
            reason: 'Reading ${i + 1} should be ~12 Mbps');

        if (previousMpbs != null) {
          // Consecutive readings should be consistent (within 0.1 Mbps)
          expect((mbps - previousMpbs).abs(), lessThan(0.1),
              reason: 'Reading ${i + 1} should be stable');
        }
        previousMpbs = mbps;
      }
    });

    test('simulates traffic spike then idle', () {
      const interval = Duration(seconds: 2);
      var totalBytes = 0;

      // 2 seconds of high traffic: 100 Mbps
      // 100 Mbps = 100 * 1,000,000 / 8 = 12,500,000 bytes/s
      // In 2 s: 25,000,000 bytes
      final mbps1 = NetworkInfoService.computeMbps(
        totalBytes,
        totalBytes + 25000000,
        interval,
      );
      expect(mbps1, closeTo(100.0, 0.1));
      totalBytes += 25000000;

      // 2 seconds of idle: 0 Mbps
      final mbps2 = NetworkInfoService.computeMbps(
        totalBytes,
        totalBytes, // no change
        interval,
      );
      expect(mbps2, 0.0);

      // 2 seconds of moderate traffic: 10 Mbps
      final mbps3 = NetworkInfoService.computeMbps(
        totalBytes,
        totalBytes + 2500000, // 2.5 MB in 2 s = 10 Mbps
        interval,
      );
      expect(mbps3, closeTo(10.0, 0.01));
    });

    test('simulates parsing netstat output then computing Mbps', () {
      const output1 = '''
Interface Statistics

                                Received             Sent

Bytes                          5000000000         2000000000
''';
      const output2 = '''
Interface Statistics

                                Received             Sent

Bytes                          5050000000         2025000000
''';

      final parsed1 = NetworkInfoService.parseNetstatOutput(output1);
      final parsed2 = NetworkInfoService.parseNetstatOutput(output2);

      expect(parsed1, isNotNull);
      expect(parsed2, isNotNull);

      final total1 = parsed1!.$1 + parsed1.$2; // 7,000,000,000
      final total2 = parsed2!.$1 + parsed2.$2; // 7,075,000,000

      // delta = 75,000,000 bytes over 2 s = 300 Mbps
      final mbps = NetworkInfoService.computeMbps(
        total1,
        total2,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(300.0, 0.1));
    });

    test('simulates real-world WiFi speeds: 50 Mbps down / 10 Mbps up', () {
      // 50 Mbps = 6,250,000 bytes/s received
      // 10 Mbps = 1,250,000 bytes/s sent
      // Total = 7,500,000 bytes/s
      // In 2 seconds = 15,000,000 bytes
      const interval = Duration(seconds: 2);
      const bytesDelta = 15000000;

      final mbps = NetworkInfoService.computeMbps(0, bytesDelta, interval);
      // (15,000,000 * 8) / (2 * 1,000,000) = 60 Mbps
      expect(mbps, closeTo(60.0, 0.1));
    });

    test('simulates slow connection: 1 Mbps', () {
      // 1 Mbps = 125,000 bytes/s
      // In 2 seconds = 250,000 bytes
      final mbps = NetworkInfoService.computeMbps(0, 250000, const Duration(seconds: 2));
      expect(mbps, closeTo(1.0, 0.001));
    });

    test('simulates gigabit ethernet: 940 Mbps', () {
      // 940 Mbps ≈ 117,500,000 bytes/s
      // In 2 seconds = 235,000,000 bytes
      final mbps = NetworkInfoService.computeMbps(
        0,
        235000000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(940.0, 0.1));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  //  Formatting — speed label rendering
  // ════════════════════════════════════════════════════════════════════════
  group('Speed label formatting', () {
    String formatSpeed(double rtMbps, bool isConnected) {
      if (!isConnected) return '';
      return '${rtMbps >= 10 ? rtMbps.toStringAsFixed(0) : rtMbps.toStringAsFixed(1)} Mbps';
    }

    test('shows 0.0 Mbps when connected but idle', () {
      expect(formatSpeed(0.0, true), '0.0 Mbps');
    });

    test('hides label when disconnected', () {
      expect(formatSpeed(0.0, false), '');
      expect(formatSpeed(42.0, false), '');
    });

    test('shows 1 decimal for < 10 Mbps', () {
      expect(formatSpeed(3.5, true), '3.5 Mbps');
      expect(formatSpeed(0.1, true), '0.1 Mbps');
      expect(formatSpeed(9.9, true), '9.9 Mbps');
    });

    test('shows integer for >= 10 Mbps', () {
      expect(formatSpeed(10.0, true), '10 Mbps');
      expect(formatSpeed(47.0, true), '47 Mbps');
      expect(formatSpeed(100.0, true), '100 Mbps');
    });

    test('formats simulated 12 Mbps reading', () {
      final mbps = NetworkInfoService.computeMbps(0, 3000000, const Duration(seconds: 2));
      expect(formatSpeed(mbps, true), '12 Mbps');
    });

    test('formats simulated 0.5 Mbps reading', () {
      final mbps = NetworkInfoService.computeMbps(0, 125000, const Duration(seconds: 2));
      expect(formatSpeed(mbps, true), '0.5 Mbps');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  //  Live netstat -e integration (runs on real machine)
  // ════════════════════════════════════════════════════════════════════════
  group('Live netstat -e integration', () {
    test('parses real netstat -e output from this machine', () async {
      if (!Platform.isWindows) {
        // Skip on non-Windows (netstat -e format differs)
        return;
      }

      final result = await Process.run('netstat', ['-e']);
      expect(result.exitCode, 0);

      final parsed = NetworkInfoService.parseNetstatOutput(result.stdout as String);
      expect(parsed, isNotNull,
          reason: 'Should find and parse the Bytes line from real netstat -e');

      final (received, sent) = parsed!;
      // Both should be non-negative integers
      expect(received, greaterThanOrEqualTo(0));
      expect(sent, greaterThanOrEqualTo(0));
    });

    test('real netstat readings are monotonically increasing', () async {
      if (!Platform.isWindows) return;

      final r1 = await Process.run('netstat', ['-e']);
      final p1 = NetworkInfoService.parseNetstatOutput(r1.stdout as String);
      expect(p1, isNotNull);

      // Wait 1 second to ensure counters advance
      await Future<void>.delayed(const Duration(seconds: 1));

      final r2 = await Process.run('netstat', ['-e']);
      final p2 = NetworkInfoService.parseNetstatOutput(r2.stdout as String);
      expect(p2, isNotNull);

      final total1 = p1!.$1 + p1.$2;
      final total2 = p2!.$1 + p2.$2;
      expect(total2, greaterThanOrEqualTo(total1),
          reason: 'Cumulative byte counters should never decrease');

      // Compute the throughput between the two readings
      final mbps = NetworkInfoService.computeMbps(
        total1,
        total2,
        const Duration(seconds: 1),
      );
      // Throughput should be non-negative and plausible (< 10 Gbps for any
      // realistic smart-board NIC)
      expect(mbps, greaterThanOrEqualTo(0.0));
      expect(mbps, lessThan(10000.0),
          reason: 'Throughput should be plausible for a local NIC');
    });

    test('complete pipeline: parse → compute → format', () async {
      if (!Platform.isWindows) return;

      // Reading 1
      final r1 = await Process.run('netstat', ['-e']);
      final p1 = NetworkInfoService.parseNetstatOutput(r1.stdout as String);
      expect(p1, isNotNull);

      await Future<void>.delayed(const Duration(seconds: 2));

      // Reading 2
      final r2 = await Process.run('netstat', ['-e']);
      final p2 = NetworkInfoService.parseNetstatOutput(r2.stdout as String);
      expect(p2, isNotNull);

      final total1 = p1!.$1 + p1.$2;
      final total2 = p2!.$1 + p2.$2;
      final mbps = NetworkInfoService.computeMbps(
        total1,
        total2,
        const Duration(seconds: 2),
      );

      final label =
          '${mbps >= 10 ? mbps.toStringAsFixed(0) : mbps.toStringAsFixed(1)} Mbps';

      // Label should be well-formed
      expect(label, endsWith('Mbps'));
      expect(label, isNot(contains('null')));
      expect(label, isNot(contains('NaN')));

      // If there was meaningful traffic (>100KB in 2 seconds = >0.4 Mbps),
      // the value should be positive. Tiny background traffic may round to 0.0.
      if (total2 - total1 > 100000) {
        expect(mbps, greaterThan(0.0));
        expect(label, isNot(equals('0.0 Mbps')));
      }
    });
  });
}
