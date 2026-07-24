import '../utils/logger.dart';
import 'enterprise_deploy_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeployConfigValidationResult
//
// Returned by [DeployConfigValidator.validate]. Contains:
//   - valid: whether the config passed all checks
//   - errors: blocking issues (config cannot be deployed)
//   - warnings: non-blocking concerns (deployable but risky)
//   - config: the original config reference
//
// Errors prevent deployment. Warnings allow deployment but should be
// reviewed by the IT admin.
// ─────────────────────────────────────────────────────────────────────────────
class DeployConfigValidationResult {
  final bool valid;
  final List<String> errors;
  final List<String> warnings;
  final EnterpriseDeployConfig config;

  const DeployConfigValidationResult({
    required this.valid,
    required this.errors,
    required this.warnings,
    required this.config,
  });

  bool get hasWarnings => warnings.isNotEmpty;
  String? get firstError => errors.isEmpty ? null : errors.first;

  /// Human-readable summary for IT admin display.
  String get summary {
    if (valid && !hasWarnings) return 'Config is valid.';
    if (valid) return 'Config is valid with ${warnings.length} warning(s).';
    return 'Config has ${errors.length} error(s) that must be fixed.';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeployConfigValidator
//
// Stateless validator for enterprise deployment configs. Checks:
//   1. Board ID format
//   2. Server URL validity
//   3. SSL fingerprint format (if provided)
//   4. Update channel validity
//   5. Firebase config completeness
//   6. Security warnings (missing SSL pin, debug-like settings)
//
// The validator is used:
//   - By IT admins before deployment (dry-run validation)
//   - By deploy_silent.ps1 (if Dart is available)
//   - By the app at startup (to verify config integrity)
// ─────────────────────────────────────────────────────────────────────────────
class DeployConfigValidator {
  DeployConfigValidator._();

  /// Validate a loaded config. Returns a result with errors and warnings.
  static DeployConfigValidationResult validate(EnterpriseDeployConfig config) {
    final errors = <String>[];
    final warnings = <String>[];

    _checkBoardId(config, errors);
    _checkServer(config, errors, warnings);
    _checkFirebase(config, warnings);
    _checkUpdate(config, warnings);
    _checkSecurity(config, warnings);

    final valid = errors.isEmpty;

    if (valid) {
      Log.i('[DeployConfigValidator] VALID — board=${config.boardId} '
          'server=${config.server.apiBaseUrl} '
          'warnings=${warnings.length}');
    } else {
      Log.w('[DeployConfigValidator] INVALID — ${errors.length} error(s): '
          '${errors.join("; ")}');
    }

    return DeployConfigValidationResult(
      valid: valid,
      errors: errors,
      warnings: warnings,
      config: config,
    );
  }

  /// Validate a config file at [path]. Returns null if file not found.
  static Future<DeployConfigValidationResult?> validateFile(String path) async {
    final config = await EnterpriseDeployConfig.loadFromFile(path);
    if (config == null) {
      return DeployConfigValidationResult(
        valid: false,
        errors: ['Config file not found or invalid JSON: $path'],
        warnings: [],
        config: const EnterpriseDeployConfig(
          boardId: '',
          server: ServerConfig(),
        ),
      );
    }
    return validate(config);
  }

  // ── Checks ──────────────────────────────────────────────────────────────

  static void _checkBoardId(
      EnterpriseDeployConfig config, List<String> errors) {
    final id = config.boardId;
    if (id.isEmpty) {
      errors.add('board_id is required');
      return;
    }
    if (!RegExp(r'^IASB-[A-Z0-9]{4,16}$').hasMatch(id)) {
      errors.add(
          'board_id must match pattern IASB-<4-16 alphanumeric chars> '
          '(got "$id")');
    }
  }

  static void _checkServer(
      EnterpriseDeployConfig config, List<String> errors, List<String> warnings) {
    final url = config.server.apiBaseUrl;
    if (url.isEmpty) {
      errors.add('server.api_base_url is required');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      errors.add('server.api_base_url is not a valid URL: "$url"');
      return;
    }

    if (uri.scheme != 'https') {
      warnings.add(
          'server.api_base_url uses ${uri.scheme} — production should use https');
    }

    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      warnings.add(
          'server.api_base_url points to localhost — is this intentional?');
    }

    // SSL pin
    final pin = config.server.sslPinFingerprint;
    if (pin != null && pin.isNotEmpty) {
      if (!RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(pin)) {
        errors.add(
            'ssl_pin_fingerprint must be 64 hex chars (got ${pin.length} chars)');
      }
    } else {
      warnings.add(
          'No SSL pin configured — certificate pinning is disabled');
    }
  }

  static void _checkFirebase(
      EnterpriseDeployConfig config, List<String> warnings) {
    final fb = config.firebase;
    if (fb.apiKey.contains('replace-with')) {
      warnings.add('Firebase API key appears to be a placeholder');
    }
    if (fb.projectId.contains('replace-with')) {
      warnings.add('Firebase project ID appears to be a placeholder');
    }
  }

  static void _checkUpdate(
      EnterpriseDeployConfig config, List<String> warnings) {
    final validChannels = {'stable', 'beta', 'internal', 'dev'};
    if (!validChannels.contains(config.update.channel)) {
      warnings.add(
          'Update channel "${config.update.channel}" is not a standard channel');
    }
    if (config.update.channel == 'dev') {
      warnings.add(
          'Update channel is "dev" — intended for development only');
    }
  }

  static void _checkSecurity(
      EnterpriseDeployConfig config, List<String> warnings) {
    if (config.server.sslPinFingerprint == null ||
        config.server.sslPinFingerprint!.isEmpty) {
      warnings.add(
          'SSL pinning disabled — man-in-the-middle attacks possible');
    }
    if (config.update.hmacSecretKey == null ||
        config.update.hmacSecretKey!.isEmpty) {
      warnings.add(
          'HMAC manifest verification disabled — manifest tampering not detected');
    }
    if (!config.features.kioskMode) {
      warnings.add(
          'Kiosk mode disabled — users can exit the application');
    }
    if (config.location == null) {
      warnings.add(
          'No location configured — Sentry fleet filtering (school, building, room) will be unavailable');
    }
  }
}
