import 'dart:convert';
import 'dart:io';

/// Where a scenario is proven.
///
/// The Phase 1 report must be honest about this: automated / CI-simulated
/// scenarios carry real verdicts; hardware-lab and fleet scenarios are
/// declared and pending until executed on real equipment / fleets.
enum ScenarioStatus {
  /// Executed inline in this suite with direct assertions.
  automated,

  /// Executed in this suite but with injected faults (servers, seams).
  ciSimulated,

  /// Requires a hardware lab (real power cut, reboot, installer + UAC).
  hardwareLab,

  /// Requires a fleet (soak, ramp, bandwidth telemetry).
  fleet,
}

/// A single validated behaviour with its evidence trail.
class ScenarioResult {
  final String id;
  final String category;
  final String title;
  final String description;
  final ScenarioStatus status;
  final String? owner;

  /// True = PASS, false = FAIL. Null for declared-but-pending scenarios.
  bool? pass;
  String? verdict;
  String? observed;
  String? error;
  String? trace;
  Duration elapsed = Duration.zero;
  DateTime ranAt = DateTime.now().toUtc();

  final List<String> evidence;
  final Map<String, String> metrics;

  ScenarioResult({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.status,
    this.owner,
  })  : evidence = [],
        metrics = {};

  String get statusLabel => switch (status) {
        ScenarioStatus.automated => 'AUTOMATED',
        ScenarioStatus.ciSimulated => 'CI-SIMULATED',
        ScenarioStatus.hardwareLab => 'HARDWARE-LAB',
        ScenarioStatus.fleet => 'FLEET',
      };

  bool get isExecuted =>
      status == ScenarioStatus.automated || status == ScenarioStatus.ciSimulated;
}

class ValidationSuite {
  ValidationSuite._();

  static final List<ScenarioResult> results = [];
  static int _counter = 0;

  static void reset() {
    results.clear();
    _counter = 0;
  }

  /// Register a scenario (automated or declared-pending).
  static ScenarioResult register({
    required String category,
    required String title,
    required String description,
    ScenarioStatus status = ScenarioStatus.ciSimulated,
    String? owner,
  }) {
    _counter++;
    final r = ScenarioResult(
      id: 'SC-${_counter.toString().padLeft(3, '0')}',
      category: category,
      title: title,
      description: description,
      status: status,
      owner: owner,
    );
    if (status == ScenarioStatus.hardwareLab ||
        status == ScenarioStatus.fleet) {
      r.verdict = 'PENDING';
      r.observed =
          'Declared — requires ${status == ScenarioStatus.hardwareLab ? 'a hardware lab' : 'a fleet deployment'} to execute';
    }
    results.add(r);
    return r;
  }

  /// Append an evidence line.
  static void note(ScenarioResult r, String line) => r.evidence.add(line);

  /// Record a measured metric.
  static void metric(ScenarioResult r, String key, String value) =>
      r.metrics[key] = value;

  /// Execute a scenario body. Any thrown error is recorded as FAIL and then
  /// rethrown so the enclosing test fails — the CI gate is enforced by the
  /// suite actually failing when a CI-testable scenario fails.
  static Future<void> run(
    ScenarioResult r,
    Future<void> Function() body,
  ) async {
    final sw = Stopwatch()..start();
    r.ranAt = DateTime.now().toUtc();
    try {
      await body();
      r.pass = true;
      r.verdict = 'PASS';
      r.observed = 'All assertions passed';
      r.elapsed = sw.elapsed;
    } catch (e, st) {
      r.pass = false;
      r.verdict = 'FAIL';
      r.error = e.toString();
      r.trace = st.toString().split('\n').take(8).join('\n');
      r.observed = 'Exception: $e';
      r.elapsed = sw.elapsed;
      rethrow;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report aggregation
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> summary() {
  final results = ValidationSuite.results;
  final executed = results.where((r) => r.isExecuted).toList();
  final passed = executed.where((r) => r.pass == true).toList();
  final failed = executed.where((r) => r.pass == false).toList();
  final pending =
      results.where((r) => !r.isExecuted).toList();

  return {
    'total': results.length,
    'executed': executed.length,
    'passed': passed.length,
    'failed': failed.length,
    'pending': pending.length,
    'automatedPassRate': executed.isEmpty
        ? null
        : (passed.length / executed.length * 100).toStringAsFixed(1),
    'gate': executed.isNotEmpty && failed.isEmpty ? 'PASS' : 'FAIL',
  };
}

/// Maps the acceptance-metrics table from the validation requirements to the
/// values actually produced (or a pending/hardware-lab marker).
Map<String, dynamic> acceptanceMetrics() {
  final executed =
      ValidationSuite.results.where((r) => r.isExecuted).toList();
  final passed = executed.where((r) => r.pass == true).length;

  return {
    'update_success_rate_ge_99.9':
        '${executed.isEmpty ? 'N/A' : '${(passed / executed.length * 100).toStringAsFixed(1)}%'} '
            'of ${executed.length} executed scenarios',
    'rollback_success_rate_100_on_injected_failures':
        'HARDWARE-LAB required (real installer/reboot restore not simulated)',
    'data_corruption_0_cases':
        'PENDING — every scenario asserted no corruption; hardware-lab pending',
    'boot_failures_after_update_0':
        'HARDWARE-LAB required (real power cut / reboot)',
    'partial_installations_0':
        'CI: download-failure scenarios assert no orphan/partial files remain',
    'state_recovery_after_unexpected_reboot_100':
        'HARDWARE-LAB required (real reboot injection)',
    'memory_leaks_none_over_repeated_runs':
        'HARDWARE-LAB required (real handle/RSS measurement)',
    'concurrent_update_exactly_one_installer':
        'CI: single-flight scenarios assert exactly one pipeline start',
    'backup_integrity_verified_every_update':
        'CI: backup created and verified before download in every pipeline scenario',
    'sha_validation_failures_accepted_0':
        'CI: every wrong-hash scenario asserts installer is deleted and never launched',
    'invalid_manifests_installed_0':
        'CI: every denied-manifest scenario asserts no download occurs',
  };
}

Map<String, dynamic> gapMatrix() {
  final byCategory = <String, Map<ScenarioStatus, int>>{};
  for (final r in ValidationSuite.results) {
    final map = byCategory.putIfAbsent(
        r.category, () => {for (final s in ScenarioStatus.values) s: 0});
    map[r.status] = map[r.status]! + 1;
  }
  return {
    for (final e in byCategory.entries)
      e.key: {
        for (final s in ScenarioStatus.values)
          s.name: e.value[s],
      },
  };
}

void writeJsonReport(String path) {
  final payload = {
    'suite': 'Phase 1 — Update System Stabilization Validation',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'environment': {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
    },
    'summary': summary(),
    'acceptance_metrics': acceptanceMetrics(),
    'gap_matrix': gapMatrix(),
    'scenarios': [
      for (final r in ValidationSuite.results)
        {
          'id': r.id,
          'category': r.category,
          'title': r.title,
          'description': r.description,
          'status': r.statusLabel,
          'owner': r.owner,
          'verdict': r.verdict,
          'observed': r.observed,
          'error': r.error,
          'elapsed_ms': r.elapsed.inMilliseconds,
          'metrics': r.metrics,
          'evidence': r.evidence,
          'trace': r.trace,
        },
    ],
  };
  File(path).createSync(recursive: true);
  File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload));
  stdout.writeln('[Validation] JSON report: $path');
}

void writeMarkdownReport(String path) {
  final s = summary();
  final b = StringBuffer();

  b.writeln('# Phase 1 Validation Report');
  b.writeln('');
  b.writeln('Update System Stabilization — self-update reliability evidence.');
  b.writeln('');
  b.writeln(
      'Generated: ${DateTime.now().toUtc().toIso8601String()} '
      'on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  b.writeln('');
  b.writeln('## Overall Verdict');
  b.writeln('');
  b.writeln('> **${s['gate']}** — ${s['passed']}/${s['executed']} executed '
      'scenarios passed (${s['automatedPassRate']}%), '
      '${s['failed']} failed, ${s['pending']} pending (hardware-lab/fleet).');
  b.writeln('');
  b.writeln(
      'A **PASS** here means every CI-testable scenario passed. It does NOT '
      'claim hardware-lab or fleet evidence — those remain PENDING.');
  b.writeln('');

  b.writeln('## Acceptance Metrics');
  b.writeln('');
  b.writeln('| Metric | Evidence |');
  b.writeln('| --- | --- |');
  for (final e in acceptanceMetrics().entries) {
    b.writeln('| ${e.key.replaceAll('_', ' ')} | ${e.value} |');
  }
  b.writeln('');

  b.writeln('## Gap Matrix');
  b.writeln('');
  b.writeln('| Category | AUTOMATED | CI-SIMULATED | HARDWARE-LAB | FLEET |');
  b.writeln('| --- | --- | --- | --- | --- |');
  for (final e in gapMatrix().entries) {
    final counts = e.value as Map<String, dynamic>;
    b.writeln('| ${e.key} | ${counts['automated']} | '
        '${counts['ciSimulated']} | ${counts['hardwareLab']} | '
        '${counts['fleet']} |');
  }
  b.writeln('');

  String? currentCategory;
  for (final r in ValidationSuite.results) {
    if (r.category != currentCategory) {
      currentCategory = r.category;
      b.writeln('## ${r.category}');
      b.writeln('');
    }
    final verdict = r.verdict ?? 'PENDING';
    final emoji = verdict == 'PASS'
        ? 'PASS'
        : verdict == 'FAIL'
            ? 'FAIL'
            : '----';
    b.writeln('### ${r.id} — ${r.title} [${r.statusLabel}]');
    b.writeln('');
    b.writeln('**Scenario:** ${r.description}');
    b.writeln('');
    b.writeln('| Field | Value |');
    b.writeln('| --- | --- |');
    b.writeln('| Verdict | **$emoji** ($verdict) |');
    b.writeln('| Expected | See description / acceptance matrix |');
    b.writeln('| Observed | ${r.observed ?? '-'} |');
    b.writeln('| Elapsed | ${r.elapsed.inMilliseconds} ms |');
    if (r.owner != null) b.writeln('| Owner | ${r.owner} |');
    if (r.error != null) b.writeln('| Error | `${r.error}` |');
    for (final m in r.metrics.entries) {
      b.writeln('| ${m.key} | ${m.value} |');
    }
    b.writeln('');
    if (r.evidence.isNotEmpty) {
      b.writeln('**Evidence**');
      b.writeln('');
      for (final line in r.evidence) {
        b.writeln('- `$line`');
      }
      b.writeln('');
    }
    if (r.trace != null) {
      b.writeln('**Failure trace**');
      b.writeln('```');
      b.writeln(r.trace);
      b.writeln('```');
      b.writeln('');
    }
  }

  File(path).createSync(recursive: true);
  File(path).writeAsStringSync(b.toString());
  stdout.writeln('[Validation] Markdown report: $path');
}
