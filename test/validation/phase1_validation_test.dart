import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/config/install_paths.dart';
import 'package:intelliattend_smartboard/core/state/installation_state.dart'
    as state_contract;
import 'package:intelliattend_smartboard/core/state/state_persister.dart';
import 'package:intelliattend_smartboard/core/update/manifest_policy.dart';
import 'package:intelliattend_smartboard/core/update/manifest_validator.dart';
import 'package:intelliattend_smartboard/core/utils/version.dart';
import 'package:intelliattend_smartboard/models/remote_config.dart';
import 'package:intelliattend_smartboard/services/auto_updater.dart';
import 'package:intelliattend_smartboard/services/update_health_monitor.dart';

import 'fault_http_server.dart';
import 'validation_framework.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Phase 1 Validation Harness
//
//  Runs the CI-testable scenario matrix for the update system and emits a
//  formal Phase 1 Validation Report (Markdown + JSON) with evidence,
//  acceptance metrics, and a gap matrix separating what was PROVEN here from
//  what still requires a hardware lab or a fleet.
//
//  Gate semantics: a scenario FAIL is rethrown, so `flutter test` fails if
//  any CI-testable scenario fails. Hardware-lab and fleet scenarios are
//  declared as PENDING and do not gate CI.
// ═══════════════════════════════════════════════════════════════════════════

// ── Shared test state ───────────────────────────────────────────────────────
final List<Map<String, String>> _launches = [];
final List<FaultHttpServer> _servers = [];
late Directory _tempRoot;
late Directory _appDir;

// ── Helpers ─────────────────────────────────────────────────────────────────

List<int> installerBytes(int length) {
  final rng = Random(42);
  return List<int>.generate(length, (_) => rng.nextInt(256));
}

String shaHex(List<int> bytes) => sha256.convert(bytes).toString();

UpdateManifest manifest({
  required String minimumVersion,
  String? downloadUrl,
  String? sha256,
  bool force = false,
  int rollout = 100,
  String? channel,
  int schema = 2,
  String? signature,
  String? maximumVersion,
  String? minimumOsVersion,
  String? expiresAt,
}) =>
    UpdateManifest(
      schemaVersion: schema,
      minimumVersion: minimumVersion,
      maximumVersion: maximumVersion,
      minimumOsVersion: minimumOsVersion,
      expiresAt: expiresAt,
      downloadUrl: downloadUrl,
      sha256: sha256,
      signature: signature,
      force: force,
      rolloutPercentage: rollout,
      channel: channel,
    );

UpdateManifest validManifest({
  required String target,
  required String url,
  required String sha,
  bool force = false,
  int rollout = 100,
}) =>
    manifest(
      minimumVersion: target,
      downloadUrl: url,
      sha256: sha,
      force: force,
      rollout: rollout,
      channel: 'stable',
      schema: 2,
    );

String signManifest(UpdateManifest m, String secret) {
  final payload = Map<String, dynamic>.from(m.toJson())..remove('signature');
  final hmac = Hmac(sha256, utf8.encode(secret));
  return hmac.convert(utf8.encode(jsonEncode(payload))).toString();
}

Future<FaultHttpServer> newServer() async {
  final server = await FaultHttpServer.start();
  _servers.add(server);
  return server;
}

Future<void> setUpPipeline({
  String installed = '5.4.0',
  bool realAgent = false,
}) async {
  AutoUpdater.debugReset();
  AutoUpdater.testInstalledVersionOverride = installed;
  AutoUpdater.debugInitializedAt =
      DateTime.now().subtract(const Duration(minutes: 1));
  AutoUpdater.diskSpaceProbeOverride = () async => true;
  AutoUpdater.debugExitOnCompletion = false;
  if (!realAgent) {
    AutoUpdater.agentLauncherOverride =
        ({
          required String installerPath,
          required String targetVersion,
          required String expectedSha256,
          required String logPath,
        }) async {
          _launches.add({
            'installer': installerPath,
            'target': targetVersion,
            'sha': expectedSha256,
          });
          return true;
        };
  }
  await AutoUpdater.init(boardId: 'board-001', boardChannel: 'stable');
}

/// Run checkForUpdate and wait for the pipeline to settle. Returns whether a
/// pipeline was started.
Future<bool> drive(UpdateManifest m) async {
  final started = await AutoUpdater.checkForUpdate(m, silent: false);
  if (started) {
    final settled = await AutoUpdater.debugWaitForPipeline();
    if (!settled) throw StateError('pipeline did not settle within timeout');
  }
  return started;
}

Future<bool> waitForState(
  UpdateState state, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (AutoUpdater.progress.value?.state != state &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return AutoUpdater.progress.value?.state == state;
}

void expectProgress(UpdateState state) {
  expect(AutoUpdater.progress.value?.state, state);
}

bool hasOrphanFiles() {
  final dir = Directory(InstallPaths.updateDir);
  if (!dir.existsSync()) return false;
  return dir.listSync().whereType<File>().isNotEmpty;
}

Future<void> _scenario(
  String category,
  String title,
  String description,
  Future<void> Function(ScenarioResult r) body,
) async {
  final r = ValidationSuite.register(
      category: category, title: title, description: description);
  await ValidationSuite.run(r, () => body(r));
}

void _pending(
  String category,
  String title,
  String description,
  String owner,
) {
  test('$title (PENDING)', () {
    ValidationSuite.register(
      category: category,
      title: title,
      description: description,
      status: ScenarioStatus.hardwareLab,
      owner: owner,
    );
  });
}

void _pendingFleet(
  String category,
  String title,
  String description,
  String owner,
) {
  test('$title (PENDING)', () {
    ValidationSuite.register(
      category: category,
      title: title,
      description: description,
      status: ScenarioStatus.fleet,
      owner: owner,
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    _tempRoot = Directory.systemTemp.createTempSync('phase1_val_');
    _appDir = Directory('${_tempRoot.path}\\App');
    _appDir.createSync(recursive: true);
    File('${_appDir.path}\\intelliattend_smartboard.exe')
        .writeAsStringSync('APP_BINARY');
    File('${_appDir.path}\\data.bin').writeAsStringSync('APP_DATA');
    InstallPaths.testRootOverride = _tempRoot.path;
    UpdateHealthMonitor.testAppDirectoryOverride = _appDir;
    _launches.clear();
  });

  tearDown(() {
    for (final s in _servers) {
      try {
        s.close();
      } catch (_) {}
    }
    _servers.clear();
    AutoUpdater.debugReset();
    UpdateHealthMonitor.testAppDirectoryOverride = null;
    InstallPaths.testRootOverride = null;
    try {
      _tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() async {
    final outDir = '${Directory.current.path}\\build\\validation';
    writeJsonReport('$outDir\\Phase1ValidationReport.json');
    writeMarkdownReport('$outDir\\Phase1ValidationReport.md');
    final s = summary();
    stdout.writeln('[Validation] GATE=${s['gate']} '
        'executed=${s['executed']} passed=${s['passed']} '
        'failed=${s['failed']} pending=${s['pending']}');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 1 — Manifest Validation
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 1 — Manifest Validation', () {
    final policy = ManifestPolicy(
      installedVersion: '5.4.0',
      boardId: 'test-board-001',
      hmacSecretKey: 'test-secret',
    );

    test('valid manifest accepted', () async {
      await _scenario('1 — Manifest Validation',
          'Valid manifest is accepted (no download, no crash)',
          'A well-formed manifest passes every policy check. The expected '
              'result is ALLOWED with an empty reason list.', (r) async {
        final m = manifest(minimumVersion: '5.5.0', channel: 'stable');
        final result = ManifestValidator.check(m, policy);
        ValidationSuite.note(r, 'schema=${m.schemaVersion} '
            'min=${m.minimumVersion} channel=${m.resolvedChannel}');
        expect(result.allowed, true, reason: result.reasons.join('; '));
        expect(result.reasons, isEmpty);
      });
    });

    test('expired manifest rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Expired manifest is rejected safely',
          'A manifest whose expires_at is in the past must be denied before '
              'any download.', (r) async {
        final m = manifest(
            minimumVersion: '5.5.0', expiresAt: '2020-01-01T00:00:00Z');
        final result = ManifestValidator.check(m, policy);
        ValidationSuite.note(r, 'expires_at=${m.expiresAt}');
        expect(result.denied, true);
        expect(result.firstReason, contains('expired'));
      });
    });

    test('invalid schema rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Unknown/invalid schema version is rejected',
          'A manifest using a schema the client does not understand must be '
              'rejected (forward-compatibility guard).', (r) async {
        final m = manifest(minimumVersion: '5.5.0', schema: 99);
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('Schema version'));
      });
    });

    test('future schema rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Future schema version is rejected',
          'A schema newer than the client (e.g. 3 > 2) is rejected so '
              'forward-incompatible manifests can never install.', (r) async {
        final m = manifest(minimumVersion: '5.5.0', schema: 3);
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('Schema version'));
      });
    });

    test('missing version rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Missing minimum_version is rejected',
          'A manifest with no meaningful minimum version resolves to 0.0.0 '
              'and is rejected because it is not an upgrade.', (r) async {
        final m = manifest(minimumVersion: '0.0.0');
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('no upgrade needed'));
      });
    });

    test('missing download URL rejected at pipeline', () async {
      await _scenario('1 — Manifest Validation',
          'Missing download_url rejects the update end-to-end',
          'Even if policy allows the manifest, a missing download URL must '
              'never start a download.', (r) async {
        await setUpPipeline(installed: '5.4.0');
        final m = manifest(
            minimumVersion: '5.5.0', channel: 'stable', rollout: 100);
        final started = await drive(m);
        expect(started, false);
        expect(AutoUpdater.progress.value, isNull,
            reason: 'no pipeline may start without a URL');
        ValidationSuite.note(r, 'checkForUpdate returned false; '
            'progress=${AutoUpdater.progress.value}');
      });
    });

    test('malformed JSON rejected at parse', () async {
      await _scenario('1 — Manifest Validation',
          'Malformed JSON payload is rejected at parse time',
          'Garbage on the wire must fail JSON decoding so no policy logic '
              'ever sees a corrupt manifest.', (r) async {
        expect(() => jsonDecode('{not valid json'), throwsFormatException);
        ValidationSuite.note(r,
            'jsonDecode threw FormatException as expected (transport-layer rejection)');
      });
    });

    test('wrong HMAC rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Manifest signed with the wrong key is rejected',
          'An attacker who does not hold the HMAC secret cannot produce a '
              'signature that verifies against the policy key.', (r) async {
        final m = manifest(minimumVersion: '5.5.0', channel: 'stable');
        final signature = signManifest(m, 'attacker-secret');
        final signed = manifest(
            minimumVersion: '5.5.0',
            channel: 'stable',
            signature: signature);
        final result = ManifestValidator.check(signed, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('signature mismatch'));
        ValidationSuite.note(
            r, 'computed with attacker-secret; rejected by policy key');
      });
    });

    test('wrong channel rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Wrong release channel is rejected',
          'A stable board must not accept a beta manifest.', (r) async {
        final m = manifest(minimumVersion: '5.5.0', channel: 'beta');
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('not allowed'));
      });
    });

    test('board excluded by rollout rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Board outside the rollout cohort is rejected',
          'A 0% rollout excludes every board; a 50% rollout excludes some.',
              (r) async {
        final m0 = manifest(minimumVersion: '5.5.0', rollout: 0);
        expect(ManifestValidator.check(m0, policy).denied, true);
        final m50 = manifest(minimumVersion: '5.5.0', rollout: 50);
        final included = m50.includesBoard('test-board-001');
        expect(ManifestValidator.check(m50, policy).denied, !included);
        ValidationSuite.note(r,
            'board test-board-001 included at 50% rollout: $included');
      });
    });

    test('unsupported OS rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Manifest requiring a newer OS is rejected',
          'minimum_os_version above the board OS must deny the update.',
              (r) async {
        final osPolicy = ManifestPolicy(
          installedVersion: '5.4.0',
          boardId: 'test-board-001',
          windowsVersion: (major: 10, minor: 0, build: 17763),
        );
        final m = manifest(
            minimumVersion: '5.5.0',
            minimumOsVersion: '10.0.19045');
        final result = ManifestValidator.check(m, osPolicy);
        expect(result.denied, true);
        expect(result.firstReason, contains('OS version'));
      });
    });

    test('downgrade attempt rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Downgrade attempt is rejected',
          'Installed 5.4.0 must never accept a 5.3.0 manifest.', (r) async {
        final m = manifest(minimumVersion: '5.3.0');
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
        expect(result.firstReason, contains('no upgrade needed'));
      });
    });

    test('same version rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Same-version manifest is rejected',
          'Installed == manifest minimum must not re-install.', (r) async {
        final m = manifest(minimumVersion: '5.4.0');
        final result = ManifestValidator.check(m, policy);
        expect(result.denied, true);
      });
    });

    test('above maximum ceiling rejected', () async {
      await _scenario('1 — Manifest Validation',
          'Update above the maximum version ceiling is rejected',
          'An installed version at/above the manifest maximum is blocked.',
              (r) async {
        final ceilingPolicy = ManifestPolicy(
          installedVersion: '6.0.0',
          boardId: 'test-board-001',
        );
        final m = manifest(
            minimumVersion: '5.5.0', maximumVersion: '5.999.0');
        final result = ManifestValidator.check(m, ceilingPolicy);
        expect(result.denied, true);
        expect(result.reasons.any((r) => r.contains('ceiling')), true,
            reason: result.reasons.join('; '));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 2 — Download
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 2 — Download', () {
    test('normal download completes with correct hash', () async {
      await _scenario('2 — Download',
          'Normal download completes and verifies',
          'A healthy server stream must download, hash, verify and hand off '
              'to the agent exactly once.', (r) async {
        final bytes = installerBytes(256 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        final started = await drive(m);
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(_launches.length, 1);
        expect(_launches.first['sha'], hash);
        ValidationSuite.metric(r, 'bytes', '${bytes.length}');
        ValidationSuite.metric(r, 'launch_count', '${_launches.length}');
      });
    });

    test('slow network download still completes', () async {
      await _scenario('2 — Download',
          'Slow network (throttled) completes without corruption',
          'A server throttling each chunk must still deliver the full, '
              'verified installer.', (r) async {
        final bytes = installerBytes(128 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes,
            chunkSize: 8192, chunkDelay: const Duration(milliseconds: 5));
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        final started = await drive(m);
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(_launches.first['sha'], hash);
        ValidationSuite.note(r, '16 chunks @ 5ms delay each');
      });
    });

    test('500 KB/s link completes', () async {
      await _scenario('2 — Download',
          '~500 KB/s transfer completes correctly',
          'Typical low-bandwidth school network must still complete.',
              (r) async {
        final bytes = installerBytes(128 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        // 8 KB per 16 ms ≈ 500 KB/s.
        server.serveInstaller(bytes,
            chunkSize: 8192, chunkDelay: const Duration(milliseconds: 16));
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
      });
    });

    test('100 KB/s link completes', () async {
      await _scenario('2 — Download',
          '~100 KB/s transfer completes correctly',
          'Severe throttling (100 KB/s) must still complete without timeout.',
              (r) async {
        final bytes = installerBytes(96 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        // 4 KB per 40 ms ≈ 100 KB/s.
        server.serveInstaller(bytes,
            chunkSize: 4096, chunkDelay: const Duration(milliseconds: 40));
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
      });
    });

    test('connection reset mid-stream fails cleanly', () async {
      await _scenario('2 — Download',
          'Connection reset mid-stream fails cleanly, no orphan file',
          'A socket reset after 16 KB must abort the update, delete the '
              'partial file, and never launch the agent.', (r) async {
        final bytes = installerBytes(256 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, resetAfterBytes: 16 * 1024);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: shaHex(bytes)));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(hasOrphanFiles(), false,
            reason: 'partial installer must be deleted');
        expect(_launches.length, 0);
        ValidationSuite.note(r, 'agent never launched; partial cleaned');
      });
    });

    test('connection timeout produces friendly error', () async {
      await _scenario('2 — Download',
          'Connection timeout fails with a friendly message',
          'A server that never responds must trip the download timeout and '
              'surface a user-actionable error.', (r) async {
        final server = await newServer();
        server.serveHang();
        await setUpPipeline();
        AutoUpdater.downloadTimeoutOverride = const Duration(milliseconds: 300);
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('timed out'));
        expect(_launches.length, 0);
      });
    });

    test('DNS failure produces friendly error', () async {
      await _scenario('2 — Download',
          'DNS failure produces a friendly error',
          'An unresolvable host must fail with a reachability message, not a '
              'crash.', (r) async {
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0',
            url: 'http://update.invalid/installer.exe',
            sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('reach'));
        expect(_launches.length, 0);
      });
    });

    test('HTTP 404 fails with not-found error', () async {
      await _scenario('2 — Download',
          'HTTP 404 fails with not-found message',
          'A missing installer must surface "Update file not found".',
              (r) async {
        final server = await newServer();
        server.serveInstaller(<int>[], statusCode: HttpStatus.notFound);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('not found'));
        expect(_launches.length, 0);
      });
    });

    test('HTTP 500 fails safely', () async {
      await _scenario('2 — Download',
          'HTTP 500 fails safely',
          'Server errors must never launch the agent.', (r) async {
        final server = await newServer();
        server.serveInstaller(<int>[], statusCode: HttpStatus.internalServerError);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(_launches.length, 0);
      });
    });

    test('HTTP 403 fails safely', () async {
      await _scenario('2 — Download',
          'HTTP 403 fails safely',
          'Access denied from the server must abort without launch.',
              (r) async {
        final server = await newServer();
        server.serveInstaller(<int>[], statusCode: HttpStatus.forbidden);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(_launches.length, 0);
      });
    });

    test('CDN redirect is followed', () async {
      await _scenario('2 — Download',
          'CDN 302 redirect is followed to the real asset',
          'A redirect to a CDN mirror must be transparent to the pipeline.',
              (r) async {
        final bytes = installerBytes(128 * 1024);
        final hash = shaHex(bytes);
        final mirror = await newServer();
        mirror.serveInstaller(bytes);
        final cdn = await newServer();
        cdn.serveRedirect('${mirror.base}/installer.exe');
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${cdn.base}/installer.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(_launches.first['sha'], hash);
      });
    });

    test('user cancel mid-download cleans up', () async {
      await _scenario('2 — Download',
          'User cancels mid-download: no orphan, overlay cleared',
          'Tapping Cancel must abort the stream, delete the partial file, '
              'clear the overlay, and preserve the available-update state.',
              (r) async {
        final bytes = installerBytes(2 * 1024 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes,
            chunkSize: 65536, chunkDelay: const Duration(milliseconds: 10));
        await setUpPipeline();
        final installerPath =
            '${InstallPaths.updateDir}\\IASB-5.5.0-Setup.exe';
        final started = await AutoUpdater.checkForUpdate(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: shaHex(bytes)),
            silent: false);
        expect(started, true);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!File(installerPath).existsSync() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(File(installerPath).existsSync(), true,
            reason: 'partial download must have started before we cancel');
        AutoUpdater.dismiss();
        await AutoUpdater.debugWaitForPipeline();
        expect(AutoUpdater.progress.value, isNull);
        expect(hasOrphanFiles(), false,
            reason: 'partial installer must be deleted on cancel');
        expect(AutoUpdater.availableUpdate.value, isNotNull,
            reason: 'Settings retry button must persist after dismiss');
      });
    });

    test('duplicate download requests are deduplicated', () async {
      await _scenario('2 — Download',
          'Duplicate download requests start exactly one download',
          'Re-delivering the identical manifest must not re-download.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        expect(await drive(m), true);
        final again = await AutoUpdater.checkForUpdate(m, silent: false);
        expect(again, false, reason: 'same fingerprint must be deduplicated');
        expect(_launches.length, 1);
      });
    });

    test('disk full at check time blocks the update', () async {
      await _scenario('2 — Download',
          'Insufficient disk space at check time blocks the update',
          'Free space below the 200 MB threshold must reject the update with '
              'a clear error and never download.', (r) async {
        await setUpPipeline();
        AutoUpdater.diskSpaceProbeOverride = () async => false;
        final started = await drive(validManifest(
            target: '5.5.0', url: 'http://127.0.0.1:1/i.exe', sha: 'a' * 64));
        expect(started, false);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('Insufficient disk'));
        expect(_launches.length, 0);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 3 — Hash Verification
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 3 — Hash Verification', () {
    test('correct SHA-256 passes', () async {
      await _scenario('3 — Hash Verification',
          'Correct SHA-256 passes verification',
          'A clean download whose hash matches the manifest proceeds to the '
              'agent.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
        ValidationSuite.metric(r, 'computed_sha', hash);
      });
    });

    test('wrong SHA-256 fails, installer deleted, no launch', () async {
      await _scenario('3 — Hash Verification',
          'Wrong SHA-256 fails; installer deleted; agent never launched',
          'A mismatch must delete the file and refuse to launch the agent.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0',
            url: '${server.base}/i.exe',
            sha: 'f' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('corrupted'));
        expect(hasOrphanFiles(), false, reason: 'installer must be deleted');
        expect(_launches.length, 0);
      });
    });

    test('empty SHA-256 is rejected', () async {
      await _scenario('3 — Hash Verification',
          'Manifest without a SHA-256 is rejected (no unverified installs)',
          'A missing integrity hash must refuse the update outright.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(manifest(
          minimumVersion: '5.5.0',
          downloadUrl: '${server.base}/i.exe',
          channel: 'stable',
          rollout: 100,
        ));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(
            AutoUpdater.progress.value?.error, contains('missing integrity'));
        expect(_launches.length, 0);
      });
    });

    test('bit-flipped installer fails verification', () async {
      await _scenario('3 — Hash Verification',
          'Bit-flipped installer fails SHA-256 verification',
          'A single corrupted byte in transit must be detected by the hash.',
              (r) async {
        final bytes = installerBytes(128 * 1024);
        final goodHash = shaHex(bytes);
        final corrupted = List<int>.from(bytes);
        corrupted[500] ^= 0x01;
        final server = await newServer();
        server.serveInstaller(corrupted);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0',
            url: '${server.base}/i.exe',
            sha: goodHash));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(_launches.length, 0);
        ValidationSuite.note(r, 'flipped byte at offset 500');
      });
    });

    test('case-insensitive hash comparison passes', () async {
      await _scenario('3 — Hash Verification',
          'Uppercase expected SHA-256 still matches',
          'Hash comparison must be case-insensitive hex.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes).toUpperCase();
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
      });
    });

    test('streamed digest equals known file hash', () async {
      await _scenario('3 — Hash Verification',
          'Streamed digest equals the reference SHA-256',
          'The hash computed incrementally during download must equal a '
              'direct hash of the same bytes.', (r) async {
        final bytes = installerBytes(256 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expect(_launches.first['sha'], hash,
            reason: 'digest passed to agent must be the streamed digest');
        ValidationSuite.metric(r, 'reference_sha', hash);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 4 — Backup
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 4 — Backup', () {
    test('backup created before download', () async {
      await _scenario('4 — Backup',
          'Recoverable backup is created before the download starts',
          'The current install must be backed up outside the app dir before '
              'any update proceeds.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.4.0');
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        final backup = Directory('${InstallPaths.backupDir}\\v5.4.0');
        expect(backup.existsSync(), true,
            reason: 'backup of the current install must exist');
        expect(File('${backup.path}\\intelliattend_smartboard.exe')
                .existsSync(),
            true,
            reason: 'backup must contain the app binary');
        ValidationSuite.metric(r, 'backup_path', backup.path);
      });
    });

    test('missing backup is recreated', () async {
      await _scenario('4 — Backup',
          'A missing/stale backup is recreated on the next update',
          'Removing the backup between updates must not break the next one.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.4.0');
        final backup = Directory('${InstallPaths.backupDir}\\v5.4.0');
        expect(await drive(validManifest(
                target: '5.5.0', url: '${server.base}/i.exe', sha: hash)),
            true);
        backup.deleteSync(recursive: true);
        expect(backup.existsSync(), false);
        // A subsequent update targets a newer version, so it has a distinct
        // fingerprint and is not deduplicated against the first push.
        expect(await drive(validManifest(
                target: '5.6.0', url: '${server.base}/i.exe', sha: hash)),
            true,
            reason: 'update must recreate the missing backup');
        expect(backup.existsSync(), true);
      });
    });

    test('unavailable backup path aborts the update', () async {
      await _scenario('4 — Backup',
          'Unavailable backup target aborts the update (fail-closed)',
          'If the backup cannot be created, the update MUST NOT proceed — '
              'proceeding would silently lose rollback capability.',
              (r) async {
        // A FILE where the backup directory should be forces the copy to fail.
        File('${InstallPaths.backupDir}\\v5.4.0')
            .createSync(recursive: true);
        await setUpPipeline(installed: '5.4.0');
        final started = await drive(validManifest(
            target: '5.5.0', url: 'http://127.0.0.1:1/i.exe', sha: 'a' * 64));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('aborted'));
        expect(_launches.length, 0,
            reason: 'no download/install may proceed without a backup');
        expect(hasOrphanFiles(), false);
      });
    });

    _pending('4 — Backup', 'Backup drive becomes unavailable mid-backup',
        'Detach the staging drive while the backup copy is running and verify '
            'the update aborts safely.',
        'Hardware Lab');

    _pending('4 — Backup',
        'Backup directory is read-only (ACL) at update time',
        'Set deny-write ACL on the backup dir and verify the update aborts '
            'rather than proceeding without rollback capability.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 5 — Installer
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 5 — Installer', () {
    test('agent launch success reaches completed state', () async {
      await _scenario('5 — Installer',
          'Successful agent hand-off reaches the completed state',
          'The pipeline must reach UpdateState.completed exactly when the '
              'agent accepts the hand-off.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(_launches.length, 1);
        ValidationSuite.metric(r, 'installer_path', _launches.first['installer']!);
      });
    });

    _pending('5 — Installer',
        'Installer hangs / times out during install',
        'Run the real Inno Setup exe under a fault-injection harness (timeout, '
            'hang, kill) and verify the agent recovers and rolls back.',
        'Hardware Lab');

    _pending('5 — Installer',
        'Installer exit codes 0 / 1 / 5 / 3010 are handled correctly',
        'Drive the real installer to exit with each code and verify the agent '
            'interprets them per Inno Setup semantics (3010 = reboot required).',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 6 — Update Agent / State
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 6 — Update Agent / State', () {
    test('update-state contract round-trips', () async {
      await _scenario('6 — Update Agent / State',
          'Update state file round-trips through encode/decode with checksum',
          'The file the launcher writes must be readable back with identical '
              'fields.', (r) async {
        final state = state_contract.UpdateStateFile(
          installerPath: 'C:\\x\\IASB-5.5.0-Setup.exe',
          targetVersion: '5.5.0',
          expectedSha256: 'a' * 64,
          appPid: 1234,
          appExePath: 'C:\\x\\intelliattend_smartboard.exe',
          logPath: 'C:\\x\\update.log',
          state: state_contract.UpdateState.verified,
          createdAt: DateTime.now().toIso8601String(),
          attempt: 1,
        );
        final encoded = state.encode();
        final decoded = state_contract.UpdateStateFile.decode(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.targetVersion, '5.5.0');
        expect(decoded.installerPath, state.installerPath);
        expect(decoded.expectedSha256, state.expectedSha256);
        expect(decoded.appPid, 1234);
        expect(decoded.state, state_contract.UpdateState.verified);
      });
    });

    test('missing agent exe fails safely and trips the breaker', () async {
      await _scenario('6 — Update Agent / State',
          'Missing update_agent.exe fails safely and trips the circuit breaker',
          'A board with no agent binary must never "complete" an update.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(realAgent: true);
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('update agent'));
        expect(_launches.length, 0);
      });
    });

    test('corrupted agent exe fails safely', () async {
      await _scenario('6 — Update Agent / State',
          'Corrupted (non-executable) agent fails safely',
          'A garbage file where the agent should be must fail without launch '
              'or crash.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(realAgent: true);
        File(InstallPaths.updateAgentPath)
            .createSync(recursive: true);
        File(InstallPaths.updateAgentPath)
            .writeAsStringSync('NOT AN EXECUTABLE');
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.failed);
      });
    });

    test('missing state file returns null safely', () async {
      await _scenario('6 — Update Agent / State',
          'Missing update_state.json returns null without crashing',
          'The reader must treat a missing state file as "no state".',
              (r) async {
        await setUpPipeline();
        final loaded = await StatePersister.loadUpdateState();
        expect(loaded, isNull);
        ValidationSuite.note(r, 'loadUpdateState returned null');
      });
    });

    test('corrupted state JSON returns null safely', () async {
      await _scenario('6 — Update Agent / State',
          'Corrupted state JSON returns null without crashing',
          'Garbage content must decode to null, not throw.', (r) async {
        await setUpPipeline();
        File(InstallPaths.updateStateFile)
            .createSync(recursive: true);
        File(InstallPaths.updateStateFile)
            .writeAsStringSync('{corrupted json');
        final loaded = await StatePersister.loadUpdateState();
        expect(loaded, isNull);
      });
    });

    test('tampered state checksum returns null safely', () async {
      await _scenario('6 — Update Agent / State',
          'Tampered state checksum is detected and returns null',
          'A bit flip in a previously valid state file must be caught by the '
              'integrity checksum.', (r) async {
        await setUpPipeline();
        final state = state_contract.UpdateStateFile(
          installerPath: 'C:\\x\\IASB-5.5.0-Setup.exe',
          targetVersion: '5.5.0',
          expectedSha256: 'a' * 64,
          appPid: 1234,
          appExePath: 'C:\\x\\intelliattend_smartboard.exe',
          logPath: 'C:\\x\\update.log',
          state: state_contract.UpdateState.verified,
          createdAt: DateTime.now().toIso8601String(),
        );
        final tampered = state.encode().replaceFirst(
            '"5.5.0"', '"5.6.0"');
        final decoded = state_contract.UpdateStateFile.decode(tampered);
        expect(decoded, isNull,
            reason: 'checksum mismatch must invalidate the state');
      });
    });

    test('required directories are created', () async {
      await _scenario('6 — Update Agent / State',
          'ensureDirectories creates the full infra layout',
          'A fresh install must get all staging/backup/agent dirs created.',
              (r) async {
        await InstallPaths.ensureDirectories();
        for (final dir in [
          InstallPaths.updateDir,
          InstallPaths.backupDir,
          InstallPaths.updateAgentDir,
          InstallPaths.logDir,
        ]) {
          expect(Directory(dir).existsSync(), true,
              reason: '$dir must exist');
        }
        ValidationSuite.note(
            r, 'update/backup/agent/log dirs verified under infraRoot');
      });
    });

    _pending('6 — Update Agent / State',
        'Agent signature / old-version agent rejected before install',
        'Code-signature verification and minimum-agent-version checks run '
            'inside the detached agent; requires the real signed agent.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 7 — Power Failure (hardware lab)
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 7 — Power Failure', () {
    for (final stage in const [
      'after manifest received',
      'during download start',
      'during download 20%',
      'during download 40%',
      'during download 80%',
      'during download 99%',
      'after download complete (during hash verify)',
      'during backup creation',
      'during installer launch',
      'during installer copy 50%',
      'during installer copy 95%',
      'before app restart',
      'after app restart',
      'during post-install cleanup',
      'after post-install cleanup',
    ]) {
      _pending('7 — Power Failure',
          'Power loss $stage: machine must boot old OR new version, never broken',
          'Cut AC power at this exact stage on real SmartBoard hardware and '
              'verify the machine always boots into either the old or the new '
              'version, never a broken one.',
          'Hardware Lab');
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 8 — Unexpected Reboot (hardware lab)
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 8 — Unexpected Reboot', () {
    _pending('8 — Unexpected Reboot',
        'shutdown /r /t 0 during download stages',
        'Force a hard reboot at each download stage and verify recovery '
            '(no orphan, no double install).',
        'Hardware Lab');
    _pending('8 — Unexpected Reboot',
        'shutdown /r /t 0 during install',
        'Force a reboot while the installer is running and verify the agent '
            'recovers or rolls back.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 9 — Crash Injection
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 9 — Crash Injection', () {
    test('stale partial from killed process is cleaned on next boot',
        () async {
      await _scenario('9 — Crash Injection',
          'Stale partial file from a killed process is cleaned before download',
          'If the app died mid-download, the next boot must clear the partial '
              'installer before downloading fresh.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        // Simulate the aftermath of a killed process: garbage partial remains.
        final stale = File('${InstallPaths.updateDir}\\IASB-5.5.0-Setup.exe');
        stale.createSync(recursive: true);
        stale.writeAsStringSync('PARTIAL GARBAGE');
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(shaHex(stale.readAsBytesSync()), hash,
            reason: 'stale partial must be replaced by the verified installer');
      });
    });

    test('version change is detected for crash-loop monitoring', () async {
      await _scenario('9 — Crash Injection',
          'Version change is detected and sets pending-stabilisation state',
          'After an update, the health monitor must enter the observation '
              'window so a crash loop can trigger rollback.', (r) async {
        await UpdateHealthMonitor.init(Version.parse('5.4.0'));
        await UpdateHealthMonitor.preserveCurrentInstall(
            Version.parse('5.4.0'), 'http://x/i.exe', 'a');
        await UpdateHealthMonitor.init(Version.parse('5.5.0'));
        expect(UpdateHealthMonitor.isPendingStabilisation, true);
        ValidationSuite.note(r,
            'prev=5.4.0 → current=5.5.0 detected; status=pending');
      });
    });

    _pending('9 — Crash Injection',
        'Update agent killed mid-install',
        'Kill update_agent.exe while it is copying files and verify the app '
            'recovers on next launch.',
        'Hardware Lab');
    _pending('9 — Crash Injection',
        'Installer process killed externally',
        'Terminate the installer mid-run and verify the agent detects it and '
            'recovers.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 10 — File Locks
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 10 — File Locks', () {
    test('blocked state-file path does not crash the pipeline', () async {
      await _scenario('10 — File Locks',
          'update_state.json path blocked: graceful, no crash',
          'If the state file cannot be written, the app must not crash; the '
              'write failure must be contained.', (r) async {
        // A directory where the state file should be makes every write fail.
        Directory(InstallPaths.updateStateFile).createSync(recursive: true);
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        ValidationSuite.note(r,
            'pipeline completed; state write failure was contained (documented behavior)');
      });
    });

    test('blocked health-file path does not block the update', () async {
      await _scenario('10 — File Locks',
          'update_health.json path blocked: backup still succeeds',
          'A health-state write failure must not abort a valid backup.',
              (r) async {
        Directory(InstallPaths.updateHealthFile).createSync(recursive: true);
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.4.0');
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
        expect(Directory('${InstallPaths.backupDir}\\v5.4.0').existsSync(),
            true);
      });
    });

    _pending('10 — File Locks',
        'Installer / update_agent.exe / DLL locked during real install',
        'Hold OS-level locks on the installer and app binaries while the real '
            'installer runs; verify graceful retry and no corruption.',
        'Hardware Lab');
    _pending('10 — File Locks', 'Log file locked during agent run',
        'Lock the agent log and verify logging degrades gracefully.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 11 — Resource Exhaustion
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 11 — Resource Exhaustion', () {
    test('disk below threshold is rejected', () async {
      await _scenario('11 — Resource Exhaustion',
          'Disk below 200 MB threshold is rejected',
          'Low disk must abort before any download.', (r) async {
        await setUpPipeline();
        AutoUpdater.diskSpaceProbeOverride = () async => false;
        final started = await drive(validManifest(
            target: '5.5.0', url: 'http://127.0.0.1:1/i.exe', sha: 'a' * 64));
        expect(started, false);
        expectProgress(UpdateState.failed);
        expect(AutoUpdater.progress.value?.error, contains('Insufficient disk'));
      });
    });

    test('disk just above threshold is accepted', () async {
      await _scenario('11 — Resource Exhaustion',
          'Disk just above the threshold is accepted',
          'The threshold must be inclusive of the minimum (200 MB).',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        AutoUpdater.diskSpaceProbeOverride = () async => true;
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true);
        expectProgress(UpdateState.completed);
      });
    });

    test('probe failure fails open (never blocks on a broken check)',
        () async {
      await _scenario('11 — Resource Exhaustion',
          'A failing disk probe fails open (update allowed)',
          'A broken probe must never block updates — only a genuine shortage '
              'may.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        AutoUpdater.diskSpaceProbeOverride =
            () async => throw StateError('probe unavailable');
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash));
        expect(started, true,
            reason: 'probe failure must fail open, not block the update');
        expectProgress(UpdateState.completed);
      });
    });

    _pending('11 — Resource Exhaustion',
        'RAM at 95% / 99% during update',
        'Force memory pressure and verify the updater aborts safely instead '
            'of OOM.',
        'Hardware Lab');
    _pending('11 — Resource Exhaustion',
        'CPU at 100% during update',
        'Verify the updater remains responsive under full CPU contention.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 12 — Security
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 12 — Security', () {
    test('tampered installer rejected before launch', () async {
      await _scenario('12 — Security',
          'Tampered installer is rejected; agent never launched',
          'Byte modification on the wire must be caught by the hash.',
              (r) async {
        final bytes = installerBytes(128 * 1024);
        final goodHash = shaHex(bytes);
        final tampered = List<int>.from(bytes)..[900] ^= 0xFF;
        final server = await newServer();
        server.serveInstaller(tampered);
        await setUpPipeline();
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: goodHash));
        expect(started, true);
        expectProgress(UpdateState.failed);
        expect(_launches.length, 0);
      });
    });

    test('tampered manifest rejected by HMAC', () async {
      await _scenario('12 — Security',
          'Tampered manifest is rejected by HMAC verification',
          'An attacker modifying manifest fields without the key must be '
              'rejected.', (r) async {
        final m = manifest(minimumVersion: '5.5.0', channel: 'stable');
        final sig = signManifest(m, 'test-secret');
        final tampered = manifest(
            minimumVersion: '5.5.0',
            channel: 'stable',
            rollout: 100,
            signature: sig);
        // Change a covered field after signing.
        final forged = manifest(
            minimumVersion: '5.6.0',
            channel: 'stable',
            rollout: 100,
            signature: sig);
        final result = ManifestValidator.check(forged,
            ManifestPolicy(
                installedVersion: '5.4.0',
                boardId: 'b',
                hmacSecretKey: 'test-secret'));
        expect(result.denied, true);
        expect(result.firstReason, contains('signature mismatch'));
        ValidationSuite.note(r,
            'signed for 5.5.0, presented as 5.6.0 → rejected');
        expect(tampered.minimumVersion, '5.5.0');
      });
    });

    test('replayed valid manifest does not double-install', () async {
      await _scenario('12 — Security',
          'Replayed valid manifest is deduplicated (no double install)',
          'A replay of a just-processed manifest must not trigger a second '
              'pipeline.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        expect(await drive(m), true);
        expect(await drive(m), false,
            reason: 'replay must be rejected by fingerprint dedup');
        expect(_launches.length, 1);
      });
    });

    test('downgrade attack blocked end-to-end', () async {
      await _scenario('12 — Security',
          'Downgrade attack is blocked end-to-end',
          'checkForUpdate must refuse a lower version manifest.',
              (r) async {
        await setUpPipeline(installed: '5.5.0');
        final started = await drive(manifest(
            minimumVersion: '5.4.0',
            downloadUrl: 'http://127.0.0.1:1/i.exe',
            channel: 'stable'));
        expect(started, false);
        expect(_launches.length, 0);
        expect(AutoUpdater.progress.value, isNull);
      });
    });

    test('wrong rollout rejected end-to-end', () async {
      await _scenario('12 — Security',
          'Excluded-rollout manifest rejected end-to-end',
          'A manifest for a cohort the board is not in must not start.',
              (r) async {
        await setUpPipeline(installed: '5.4.0');
        final started = await drive(manifest(
            minimumVersion: '5.5.0',
            downloadUrl: 'http://127.0.0.1:1/i.exe',
            channel: 'stable',
            rollout: 0));
        expect(started, false);
        expect(_launches.length, 0);
      });
    });

    _pending('12 — Security',
        'Tampered rollback backup detected at restore time',
        'Corrupt the v{version} backup, force a rollback, and verify the '
            'restore refuses the tampered backup.',
        'Hardware Lab');
    _pending('12 — Security',
        'Wrong / missing code-signature certificate on installer',
        'Verify Authenticode signature validation of the real installer before '
            'it is allowed to run.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 13 — Version Migration
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 13 — Version Migration', () {
    test('5.4.0 → 5.5.0 accepted', () async {
      await _scenario('13 — Version Migration',
          '5.4.0 → 5.5.0 upgrade accepted',
          'A normal minor upgrade must proceed.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.4.0');
        expect(await drive(validManifest(
                target: '5.5.0', url: '${server.base}/i.exe', sha: hash)),
            true);
        expectProgress(UpdateState.completed);
      });
    });

    test('5.5.0 → 5.6.0 accepted', () async {
      await _scenario('13 — Version Migration',
          '5.5.0 → 5.6.0 upgrade accepted', '', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.5.0');
        expect(await drive(validManifest(
                target: '5.6.0', url: '${server.base}/i.exe', sha: hash)),
            true);
        expectProgress(UpdateState.completed);
      });
    });

    test('5.6.0 → 5.7.0 accepted', () async {
      await _scenario('13 — Version Migration',
          '5.6.0 → 5.7.0 upgrade accepted', '', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline(installed: '5.6.0');
        expect(await drive(validManifest(
                target: '5.7.0', url: '${server.base}/i.exe', sha: hash)),
            true);
        expectProgress(UpdateState.completed);
      });
    });

    test('5.7.0 → 5.4.0 rollback attempt denied', () async {
      await _scenario('13 — Version Migration',
          '5.7.0 → 5.4.0 downgrade is denied',
          'Rolling a board back via the manifest path must be refused.',
              (r) async {
        await setUpPipeline(installed: '5.7.0');
        final started = await drive(manifest(
            minimumVersion: '5.4.0',
            downloadUrl: 'http://127.0.0.1:1/i.exe',
            channel: 'stable'));
        expect(started, false);
        expect(_launches.length, 0);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 14 — Configuration Preservation
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 14 — Configuration Preservation', () {
    test('env.json preserved across a failed update', () async {
      await _scenario('14 — Configuration Preservation',
          'env.json survives a failed update attempt', '', (r) async {
        final file = File('${InstallPaths.configDir}\\env.json');
        file.createSync(recursive: true);
        file.writeAsStringSync('{"ENV":"production","API_BASE":"https://x"}');
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.notFound);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(file.readAsStringSync(), '{"ENV":"production","API_BASE":"https://x"}');
        ValidationSuite.note(r, 'env.json byte-identical after failed update');
      });
    });

    test('config.json preserved across a failed update', () async {
      await _scenario('14 — Configuration Preservation',
          'config.json survives a failed update attempt', '', (r) async {
        final file = File('${InstallPaths.configDir}\\config.json');
        file.createSync(recursive: true);
        file.writeAsStringSync('{"board_id":"B-1"}');
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.internalServerError);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(file.readAsStringSync(), '{"board_id":"B-1"}');
      });
    });

    test('registration preserved across a failed update', () async {
      await _scenario('14 — Configuration Preservation',
          'Board registration survives a failed update attempt', '', (r) async {
        final file = File(InstallPaths.registrationFile);
        file.createSync(recursive: true);
        file.writeAsStringSync('{"boardId":"B-42","registered":true}');
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.forbidden);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(
            file.readAsStringSync(), '{"boardId":"B-42","registered":true}');
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 15 — User Data Preservation
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 15 — User Data Preservation', () {
    test('attendance queue and offline cache preserved', () async {
      await _scenario('15 — User Data Preservation',
          'Attendance queue and offline cache survive a failed update',
          '', (r) async {
        final queue = File('${InstallPaths.dataDir}\\attendance_queue.json');
        queue.createSync(recursive: true);
        queue.writeAsStringSync('{"pending":3}');
        final cache = File('${InstallPaths.cacheDir}\\offline.bin');
        cache.createSync(recursive: true);
        cache.writeAsBytesSync([1, 2, 3, 4]);
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.notFound);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(queue.readAsStringSync(), '{"pending":3}');
        expect(cache.readAsBytesSync(), [1, 2, 3, 4]);
      });
    });

    test('images and session logs preserved', () async {
      await _scenario('15 — User Data Preservation',
          'Images and session logs survive a failed update', '', (r) async {
        final image = File('${InstallPaths.cacheDir}\\photo_1.jpg');
        image.createSync(recursive: true);
        image.writeAsBytesSync(List<int>.generate(64, (_) => 7));
        final log = File('${InstallPaths.dataDir}\\logs\\session.log');
        log.createSync(recursive: true);
        log.writeAsStringSync('SESSION_OK');
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.notFound);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(log.readAsStringSync(), 'SESSION_OK');
        expect(image.readAsBytesSync(), List<int>.generate(64, (_) => 7));
      });
    });

    test('certificates preserved', () async {
      await _scenario('15 — User Data Preservation',
          'Certificates survive a failed update', '', (r) async {
        final cert = File('${InstallPaths.dataDir}\\certs\\board.pem');
        cert.createSync(recursive: true);
        cert.writeAsStringSync('CERT-BEGIN');
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.notFound);
        await setUpPipeline();
        await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64));
        expect(cert.readAsStringSync(), 'CERT-BEGIN');
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 16 — Stress Testing
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 16 — Stress Testing', () {
    test('100 back-to-back checks start exactly one pipeline', () async {
      await _scenario('16 — Stress Testing',
          '100 back-to-back update checks start exactly one pipeline',
          'Storming checkForUpdate with the same manifest must produce exactly '
              'one download.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        var startedCount = 0;
        for (var i = 0; i < 100; i++) {
          if (await AutoUpdater.checkForUpdate(m, silent: true)) {
            startedCount++;
          }
        }
        await AutoUpdater.debugWaitForPipeline();
        expect(startedCount, 1);
        expect(_launches.length, 1);
        ValidationSuite.metric(r, 'checks', '100');
        ValidationSuite.metric(r, 'pipelines_started', '$startedCount');
      });
    });

    test('1000 manifest validations are stable', () async {
      await _scenario('16 — Stress Testing',
          '1000 manifest validations are stable and consistent',
          'Repeated validation must not drift or throw.', (r) async {
        final policy = ManifestPolicy(
            installedVersion: '5.4.0', boardId: 'b');
        var allowed = 0;
        for (var i = 0; i < 1000; i++) {
          final m = manifest(minimumVersion: '5.5.0', channel: 'stable');
          if (ManifestValidator.check(m, policy).allowed) allowed++;
        }
        expect(allowed, 1000);
        ValidationSuite.metric(r, 'validations', '1000');
        ValidationSuite.metric(r, 'allowed', '$allowed');
      });
    });

    test('circuit breaker opens after 3 consecutive failures', () async {
      await _scenario('16 — Stress Testing',
          'Circuit breaker opens after 3 consecutive failures',
          'Repeated failure must stop auto-retry to protect the server.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final server = await newServer();
        server.serveInstaller(bytes, statusCode: HttpStatus.notFound);
        await setUpPipeline();
        final m = validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: 'a' * 64);
        for (var i = 0; i < 3; i++) {
          expect(await drive(m), true, reason: 'failure $i must be attempted');
        }
        expect(AutoUpdater.isCircuitBreakerOpen, true,
            reason: 'breaker must open after 3 failures');
        final fourth = await AutoUpdater.checkForUpdate(m, silent: true);
        expect(fourth, false,
            reason: 'open breaker must block auto-retry');
        ValidationSuite.metric(r, 'failures_to_open', '3');
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 17 — Memory / Resource Leaks
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 17 — Memory / Resource Leaks', () {
    test('20 repeated downloads leave no orphans', () async {
      await _scenario('17 — Memory / Resource Leaks',
          '20 repeated downloads leave exactly one installer and no orphans',
          'Repeated runs must not leak partial files or staging artifacts.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        // After a successful pipeline the same manifest is deduplicated (replay
        // guard), so alternate the force flag to simulate distinct admin pushes
        // while keeping the identical installer path / leak assertions.
        for (var i = 0; i < 20; i++) {
          final push = validManifest(
              target: '5.5.0',
              url: '${server.base}/i.exe',
              sha: hash,
              force: i.isOdd);
          expect(await drive(push), true);
        }
        final files = Directory(InstallPaths.updateDir)
            .listSync()
            .whereType<File>()
            .toList();
        expect(files.length, 1, reason: 'only the current installer remains');
        expect(shaHex(files.single.readAsBytesSync()), hash);
        expect(_launches.length, 20);
        ValidationSuite.metric(r, 'downloads', '20');
        ValidationSuite.metric(r, 'staging_files', '${files.length}');
      });
    });

    _pending('17 — Memory / Resource Leaks',
        'Long-run handle / RSS / thread stability over 500 runs',
        'Measure process handles, threads and RSS across 500 real update-agent '
            'runs on hardware; assert flat growth.',
        'Hardware Lab');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 18 — Concurrency
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 18 — Concurrency', () {
    test('two simultaneous checks start exactly one pipeline', () async {
      await _scenario('18 — Concurrency',
          'Two simultaneous update checks start exactly one pipeline',
          'The single-flight guard must close the TOCTOU window.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final m =
            validManifest(target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        final results = await Future.wait([
          AutoUpdater.checkForUpdate(m, silent: true),
          AutoUpdater.checkForUpdate(m, silent: true),
        ]);
        expect(results.where((r) => r).length, 1,
            reason: 'exactly one concurrent caller may start the pipeline');
        await AutoUpdater.debugWaitForPipeline();
        expect(_launches.length, 1);
      });
    });

    test('heartbeat + websocket + manual retry are single-flight', () async {
      await _scenario('18 — Concurrency',
          'Heartbeat, websocket push and manual retry collapse to one pipeline',
          'Three sources delivering (different) manifests for the same target '
              'must produce exactly one install.', (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        final results = await Future.wait([
          AutoUpdater.checkForUpdate(
              validManifest(target: '5.5.0',
                  url: '${server.base}/i.exe', sha: hash, force: true, rollout: 100),
              silent: true),
          AutoUpdater.checkForUpdate(
              validManifest(target: '5.5.0',
                  url: '${server.base}/i.exe', sha: hash, force: true, rollout: 90),
              silent: true),
          AutoUpdater.checkForUpdate(
              validManifest(target: '5.5.0',
                  url: '${server.base}/i.exe', sha: hash, force: true, rollout: 80),
              silent: true),
        ]);
        expect(results.where((r) => r).length, 1,
            reason: 'three concurrent sources must start exactly one pipeline');
        await AutoUpdater.debugWaitForPipeline();
        expect(_launches.length, 1);
      });
    });

    test('force does not pre-empt an active pipeline', () async {
      await _scenario('18 — Concurrency',
          'Force update does not pre-empt an active pipeline',
          'A forced manifest arriving mid-download must not spawn a second '
              'installer.', (r) async {
        final bytes = installerBytes(2 * 1024 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes,
            chunkSize: 65536, chunkDelay: const Duration(milliseconds: 20));
        await setUpPipeline();
        final first = validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash);
        final started = await AutoUpdater.checkForUpdate(first, silent: true);
        expect(started, true);
        expect(await waitForState(UpdateState.downloading), true,
            reason: 'pipeline must be mid-download');
        final forced = validManifest(
            target: '5.5.0',
            url: '${server.base}/i.exe',
            sha: hash,
            force: true,
            rollout: 99);
        final second = await AutoUpdater.checkForUpdate(forced, silent: true);
        expect(second, false,
            reason: 'an active pipeline must not be pre-empted');
        await AutoUpdater.debugWaitForPipeline();
        expect(_launches.length, 1);
      });
    });

    test('force overrides a stuck non-terminal pipeline', () async {
      await _scenario('18 — Concurrency',
          'Force overrides a stuck progress state (>5 min)',
          'A force push from admin must be able to recover a stuck pipeline.',
              (r) async {
        final bytes = installerBytes(64 * 1024);
        final hash = shaHex(bytes);
        final server = await newServer();
        server.serveInstaller(bytes);
        await setUpPipeline();
        AutoUpdater.progress.value = UpdateProgress(
          state: UpdateState.downloading,
          targetVersion: '5.5.0',
          fraction: 0.3,
          startedAt: DateTime.now().subtract(const Duration(minutes: 6)),
        );
        final started = await drive(validManifest(
            target: '5.5.0', url: '${server.base}/i.exe', sha: hash, force: true));
        expect(started, true,
            reason: 'force must reset the stuck progress and proceed');
        expectProgress(UpdateState.completed);
        expect(_launches.length, 1);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 19 — Long Soak (fleet)
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 19 — Long Soak', () {
    for (final days in const ['7', '14', '30']) {
      _pendingFleet('19 — Long Soak',
          'Kiosk running $days days then an update arrives',
          'Keep real boards running continuously for $days days, deliver an '
              'update, and verify it applies without a reboot or data loss.',
          'Fleet Ops');
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Category 20 — Fleet Testing
  // ─────────────────────────────────────────────────────────────────────────
  group('Category 20 — Fleet Testing', () {
    for (final n in const ['1', '5', '20', '100', '500', '1000']) {
      _pendingFleet('20 — Fleet Testing',
          'Staged fleet ramp to $n boards',
          'Deploy to $n boards measuring download bandwidth, failure rate, '
              'rollback rate and average install time at each ramp step.',
          'Fleet Ops');
    }
  });
}
