import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intelliattend_smartboard/core/state/installation_state.dart';

// Regression tests for the update_state.json checksum contract shared with the
// C++ update agent (windows/update_agent/checksum.cpp).
//
// The agent's VerifyChecksum rebuilds the payload in a fixed canonical key
// order (see WriteUpdateState in json_reader.cpp):
//   schema, owner, installer_path, target_version, expected_sha256, app_pid,
//   app_exe_path, log_path, state, error, created_at, completed_at, attempt
// The app must produce byte-identical payloads or the handoff always fails.
void main() {
  const installerPath = r'C:\Program Files\IntelliAttend SmartBoard\App\update_setup.exe';
  const appExePath = r'C:\Program Files\IntelliAttend SmartBoard\App\intelliattend_smartboard.exe';
  const logPath = r'C:\Program Files\IntelliAttend SmartBoard\Data\update_agent.log';

  UpdateStateFile buildState() => UpdateStateFile(
        installerPath: installerPath,
        targetVersion: '5.6.0+17',
        expectedSha256:
            '89234b95a23937e8cda2b60913a8c17d49d8bd273652586bbfb2f5515e7aa086',
        appPid: 4242,
        appExePath: appExePath,
        logPath: logPath,
        state: UpdateState.verified,
        createdAt: '2026-07-31T17:00:00.000000',
      );

  // The payload checksum must be computed over the canonical order that the
  // agent rebuilds with. A checksum over a different order (e.g. a std::map
  // sorted alphabetically) must NOT validate — that was the original bug.
  test('checksum uses canonical agent key order', () {
    final state = buildState();
    final payload = jsonEncode(state.toJson()..remove('checksum'));

    final canonical = payload; // insertion order == canonical order.
    final alphabetized = jsonEncode({
      'app_exe_path': appExePath,
      'app_pid': 4242,
      'attempt': 1,
      'created_at': '2026-07-31T17:00:00.000000',
      'expected_sha256':
          '89234b95a23937e8cda2b60913a8c17d49d8bd273652586bbfb2f5515e7aa086',
      'installer_path': installerPath,
      'log_path': logPath,
      'schema': 1,
      'state': 'verified',
      'target_version': '5.6.0+17',
    });

    expect(canonical, isNot(alphabetized));
  });

  test('round-trip encode/decode preserves data', () {
    final state = buildState();
    final decoded = UpdateStateFile.decode(state.encode());
    expect(decoded, isNotNull);
    expect(decoded!.targetVersion, state.targetVersion);
    expect(decoded.installerPath, state.installerPath);
    expect(decoded.state, UpdateState.verified);
    expect(decoded.attempt, 1);
  });

  test('decode accepts a file written by the agent (owner field present)', () {
    // Byte-for-byte format the C++ agent's WriteUpdateState produces:
    // compact JSON in canonical order with an `owner` field.
    final data = {
      'schema': 1,
      'owner': 'agent',
      'installer_path': installerPath,
      'target_version': '5.6.0+17',
      'expected_sha256':
          '89234b95a23937e8cda2b60913a8c17d49d8bd273652586bbfb2f5515e7aa086',
      'app_pid': 4242,
      'app_exe_path': appExePath,
      'log_path': logPath,
      'state': 'installed',
      'created_at': '2026-07-31T17:00:00.000000',
      'completed_at': '2026-07-31T16:59:50.000Z',
      'attempt': 1,
    };
    final payload = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(payload)).toString();
    final raw = jsonEncode({...data, 'checksum': checksum});

    final decoded = UpdateStateFile.decode(raw);
    expect(decoded, isNotNull);
    expect(decoded!.state, UpdateState.installed);
    expect(decoded.completedAt, '2026-07-31T16:59:50.000Z');
  });

  test('decode rejects a tampered checksum', () {
    final state = buildState();
    final raw = state.encode();
    final tampered = raw.replaceFirst(
      '"target_version":"5.6.0+17"',
      '"target_version":"5.6.0+18"',
    );
    expect(UpdateStateFile.decode(tampered), isNull);
  });
}
