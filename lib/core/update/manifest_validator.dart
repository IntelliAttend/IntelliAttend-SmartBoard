import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/remote_config.dart';
import '../utils/logger.dart';
import '../utils/version.dart';
import 'manifest_policy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ManifestValidationResult
//
// Returned by [ManifestValidator.check]. Contains:
//   - allowed: whether the manifest may proceed to download
//   - reasons: list of denial reasons (empty when allowed)
//   - manifest: the original manifest reference
//
// When allowed, [reasons] is empty and the download may proceed.
// When denied, [reasons] contains every failing constraint. This is useful
// for logging and diagnostics — the caller sees the full picture, not just
// the first failure.
// ─────────────────────────────────────────────────────────────────────────────
class ManifestValidationResult {
  /// Whether the manifest passed all policy checks.
  final bool allowed;

  /// Human-readable denial reasons. Empty when [allowed] is true.
  final List<String> reasons;

  /// The manifest that was evaluated.
  final UpdateManifest manifest;

  const ManifestValidationResult({
    required this.allowed,
    required this.reasons,
    required this.manifest,
  });

  /// Convenience: the update may proceed.
  bool get denied => !allowed;

  /// The first denial reason, or null if allowed.
  String? get firstReason => reasons.isEmpty ? null : reasons.first;

  @override
  String toString() {
    if (allowed) return 'ManifestValidationResult(ALLOWED)';
    return 'ManifestValidationResult(DENIED: ${reasons.join("; ")})';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ManifestValidator
//
// Stateless policy enforcer. Every public method is static and side-effect
// free (aside from logging). The validator reads Platform.version for OS
// checks but does not modify any state.
//
// ── Check Order ──────────────────────────────────────────────────────────────
// Checks are evaluated in a fixed order. All failures are collected before
// returning — the caller sees every denial, not just the first.
//
//   1. Schema version
//   2. Manifest expiry
//   3. Release channel
//   4. Update direction (downgrade protection)
//   5. Version range (minimum / maximum)
//   6. OS compatibility
//   7. Rollout inclusion
//   8. HMAC signature (if configured)
//
// ── Thread Safety ────────────────────────────────────────────────────────────
// All methods are pure functions of their arguments. No shared mutable state.
// Safe to call from any isolate.
//
// ─────────────────────────────────────────────────────────────────────────────
class ManifestValidator {
  ManifestValidator._();

  /// Current schema version supported by this client.
  /// Increment when the manifest format changes.
  static const int currentSchemaVersion = 2;

  /// Supported schema versions. The client accepts any version in this set.
  static const Set<int> supportedSchemaVersions = {1, 2};

  // ── Main Entry Point ────────────────────────────────────────────────────

  /// Evaluate [manifest] against [policy]. Returns a result indicating
  /// whether the update may proceed and, if denied, why.
  ///
  /// The check is comprehensive: all applicable constraints are evaluated
  /// regardless of earlier failures. This gives the caller the full picture.
  static ManifestValidationResult check(
      UpdateManifest manifest, ManifestPolicy policy) {
    final reasons = <String>[];

    _checkSchema(manifest, policy, reasons);
    _checkExpiry(manifest, reasons);
    _checkChannel(manifest, policy, reasons);
    _checkVersionRange(manifest, policy, reasons);
    _checkOsCompatibility(manifest, policy, reasons);
    _checkRollout(manifest, policy, reasons);
    _checkSignature(manifest, policy, reasons);

    if (reasons.isEmpty) {
      Log.i('[ManifestValidator] ALLOWED — v${manifest.minimumVersion} '
          'ch=${manifest.resolvedChannel} schema=${manifest.schemaVersion}');
    } else {
      Log.w('[ManifestValidator] DENIED — ${reasons.length} violation(s): '
          '${reasons.join(" | ")}');
    }

    return ManifestValidationResult(
      allowed: reasons.isEmpty,
      reasons: reasons,
      manifest: manifest,
    );
  }

  // ── Individual Checks ──────────────────────────────────────────────────

  /// Check 1: Schema version must be in the client's accepted set.
  static void _checkSchema(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    // If the policy specifies accepted versions, use that set.
    // Otherwise fall back to the client's built-in supported set.
    final accepted = policy.acceptedSchemaVersions ?? supportedSchemaVersions;
    if (!accepted.contains(manifest.schemaVersion)) {
      reasons.add(
          'Schema version ${manifest.schemaVersion} not in accepted set $accepted');
    }
  }

  /// Check 2: Manifest must not have expired.
  static void _checkExpiry(UpdateManifest manifest, List<String> reasons) {
    if (manifest.isExpired) {
      reasons.add(
          'Manifest expired at ${manifest.expiresAt} (current: ${DateTime.now().toIso8601String()})');
    }
  }

  /// Check 3: Release channel must be acceptable for this board.
  static void _checkChannel(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    final manifestChannel = manifest.resolvedChannel;
    if (!policy.isChannelAllowed(manifestChannel)) {
      reasons.add(
          'Channel "$manifestChannel" not allowed for board channel "${policy.boardChannel}" '
          '(allowed: ${policy.boardChannel}, ${policy.allowedChannels?.join(", ") ?? "none"})');
    }
  }

  /// Check 4+5: Version range validation.
  ///
  /// - Must be an upgrade (installed < manifest minimum), not a downgrade.
  /// - Must not exceed the maximum version ceiling.
  static void _checkVersionRange(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    final installed = Version.parse(policy.installedVersion);
    final manifestMin = manifest.parsedMinimum;
    final manifestMax = manifest.parsedMaximum;

    // Must be strictly newer than installed (upgrade only).
    if (installed >= manifestMin) {
      reasons.add(
          'Installed v$installed >= manifest minimum v$manifestMin (no upgrade needed)');
    }

    // Must not exceed maximum version ceiling.
    if (manifestMax != null && installed >= manifestMax) {
      reasons.add(
          'Installed v$installed >= manifest maximum v$manifestMax (update blocked by ceiling)');
    }
  }

  /// Check 6: OS version must meet the manifest's minimum requirement.
  static void _checkOsCompatibility(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    if (manifest.minimumOsVersion == null) return;

    final boardOs = policy.windowsVersion;
    if (boardOs == null) {
      reasons.add(
          'Cannot verify OS compatibility — platform version unavailable');
      return;
    }

    final required = _parseOsVersion(manifest.minimumOsVersion!);
    if (required == null) {
      reasons.add(
          'Cannot parse manifest minimum_os_version "${manifest.minimumOsVersion}"');
      return;
    }

    // Compare as (major, minor, build) tuples.
    final boardTuple = (boardOs.major, boardOs.minor, boardOs.build);
    final requiredTuple = (required.major, required.minor, required.build);

    if (_tupleLessThan(boardTuple, requiredTuple)) {
      reasons.add(
          'OS version ${boardOs.major}.${boardOs.minor}.${boardOs.build} '
          '< required ${required.major}.${required.minor}.${required.build}');
    }
  }

  /// Check 7: Board must be in the rollout cohort.
  static void _checkRollout(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    if (manifest.force) return; // Force bypasses rollout check.
    if (!manifest.includesBoard(policy.boardId)) {
      reasons.add(
          'Board ${policy.boardId} not in rollout cohort '
          '(${manifest.rolloutPercentage}%)');
    }
  }

  /// Check 8: HMAC-SHA256 signature verification.
  ///
  /// If the policy provides an hmacSecretKey and the manifest includes a
  /// signature, the validator recomputes the HMAC over the manifest payload
  /// and compares it to the provided signature.
  ///
  /// This prevents tampered manifests from being accepted by the client.
  /// The signature covers all fields except "signature" itself.
  static void _checkSignature(
      UpdateManifest manifest, ManifestPolicy policy, List<String> reasons) {
    // Skip if no secret key configured or no signature present.
    if (policy.hmacSecretKey == null || manifest.signature == null) return;
    if (policy.hmacSecretKey!.isEmpty || manifest.signature!.isEmpty) return;

    try {
      // Build the payload from the manifest JSON (excluding "signature").
      final payloadJson = Map<String, dynamic>.from(manifest.toJson())
        ..remove('signature');
      final payloadStr = jsonEncode(payloadJson);

      final keyBytes = utf8.encode(policy.hmacSecretKey!);
      final payloadBytes = utf8.encode(payloadStr);
      final hmacSha256 = Hmac(sha256, keyBytes);
      final computedSignature = hmacSha256.convert(payloadBytes).toString();

      if (computedSignature != manifest.signature) {
        reasons.add(
            'HMAC signature mismatch — manifest may have been tampered with');
      }
    } catch (e) {
      reasons.add('HMAC verification failed: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static ({int major, int minor, int build})? _parseOsVersion(String version) {
    final parts = version.split('.');
    if (parts.length < 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final build = int.tryParse(parts[2]);
    if (major == null || minor == null || build == null) return null;
    return (major: major, minor: minor, build: build);
  }

  /// Tuple comparison: a < b lexicographically.
  static bool _tupleLessThan(
      (int, int, int) a, (int, int, int) b) {
    if (a.$1 != b.$1) return a.$1 < b.$1;
    if (a.$2 != b.$2) return a.$2 < b.$2;
    return a.$3 < b.$3;
  }
}
