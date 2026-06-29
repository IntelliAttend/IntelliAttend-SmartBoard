import '../core/utils/version.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateManifest
//
// Carried inside a heartbeat response (or served from a dedicated
// GET /api/v1/board/check-update endpoint) to tell the board that a
// new binary is available.
//
// The board compares its installed version against [minimumVersion]. If the
// installed version is older and [force] is true, the AutoUpdater downloads
// and installs the MSI immediately, showing a full-screen overlay. If [force]
// is false, the board may defer the download to a maintenance window.
//
// ── Security ────────────────────────────────────────────────────────────────
// The [sha256] field lets the client verify the MSI file before running it.
// In production the MSI should also be Authenticode-signed; the client may
// optionally verify the signature via WinTrust API (cf. AutoUpdater._verify).
// ─────────────────────────────────────────────────────────────────────────────
class UpdateManifest {
  /// The minimum acceptable version (e.g. "5.5.0"). If the board's current
  /// version is strictly less than this, an update is needed.
  final String minimumVersion;

  /// Full HTTPS URL to the MSI package.
  final String? downloadUrl;

  /// SHA-256 hex digest of the MSI (64 hex chars). Verified client-side before
  /// installation. If null, hash verification is skipped.
  final String? sha256;

  /// If true the board must update immediately (blocking overlay). If false the
  /// board may prompt the user or wait for idle time.
  final bool force;

  /// Rollout percentage (0–100). A board maps its stable board ID hash to this
  /// range to decide whether it is in the canary cohort.
  final int rolloutPercentage;

  /// Human-readable release notes (markdown-ish plain text).
  final String? releaseNotes;

  /// ISO-8601 timestamp of when this manifest was published.
  final String? publishedAt;

  const UpdateManifest({
    required this.minimumVersion,
    this.downloadUrl,
    this.sha256,
    this.force = false,
    this.rolloutPercentage = 100,
    this.releaseNotes,
    this.publishedAt,
  });

  /// Deserialise from the JSON sub-object returned by the server.
  ///
  /// Expected shape:
  /// ```json
  /// {
  ///   "minimum_version": "5.5.0",
  ///   "download_url": "https://cdn.example.com/iasb-5.5.0.msi",
  ///   "sha256": "abc123...",
  ///   "force": true,
  ///   "rollout_percentage": 25,
  ///   "release_notes": "Fixed QR crash on rapid scan",
  ///   "published_at": "2026-06-28T12:00:00Z"
  /// }
  /// ```
  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      minimumVersion: json['minimum_version']?.toString() ?? '0.0.0',
      downloadUrl: json['download_url']?.toString(),
      sha256: json['sha256']?.toString(),
      force: json['force'] == true,
      rolloutPercentage: _parseInt(json['rollout_percentage'], 100),
      releaseNotes: json['release_notes']?.toString(),
      publishedAt: json['published_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'minimum_version': minimumVersion,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (sha256 != null) 'sha256': sha256,
        'force': force,
        'rollout_percentage': rolloutPercentage,
        if (releaseNotes != null) 'release_notes': releaseNotes,
        if (publishedAt != null) 'published_at': publishedAt,
      };

  /// The parsed [minimumVersion] to avoid re-parsing on every comparison.
  Version get parsedMinimum {
    try {
      return Version.parse(minimumVersion);
    } catch (_) {
      return Version.zero;
    }
  }

  /// Whether this manifest targets this board based on [boardId]'s hash and
  /// [rolloutPercentage].
  ///
  /// This enables canary / staged rollouts: set rolloutPercentage to 5, only
  /// 5 % of boards (deterministically chosen by board ID hash) will see the
  /// update.
  bool includesBoard(String boardId) {
    if (rolloutPercentage >= 100) return true;
    if (rolloutPercentage <= 0) return false;
    final hash = boardId.hashCode.abs();
    return (hash % 100) < rolloutPercentage;
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RemoteConfig
//
// The root config object that the server sends in the heartbeat response's
// `config` field. It carries:
//   - Feature flags     (instant kill-switches for any feature)
//   - UI overrides      (labels, branding, themes)
//   - Update manifest   (binary update info)
//
// The board applies this config immediately upon receiving it.
// ─────────────────────────────────────────────────────────────────────────────
class RemoteConfig {
  /// Monotonically increasing version number. The client ignores configs whose
  /// version is ≤ the last applied version to avoid re-applying stale configs.
  final int configVersion;

  /// Arbitrary key/value pairs representing feature flags.
  ///
  /// Convention: keys are snake_case strings like `"enable_analytics"`,
  /// `"enable_documents"`, `"kiosk_mode"`. Values are typically booleans but
  /// may be strings or numbers for richer configuration (e.g. interval ms).
  final Map<String, dynamic> flags;

  /// UI branding and label overrides.
  ///
  /// Example:
  /// ```json
  /// {
  ///   "branding": { "title": "IntelliAttend SmartBoard" },
  ///   "labels": { "welcome_text": "Welcome to Smart Class" }
  /// }
  /// ```
  final Map<String, dynamic> ui;

  /// Optional update manifest. When present and non-null the board should
  /// check whether a binary update is needed.
  final UpdateManifest? update;

  /// Server timestamp of when this config was generated.
  final String? issuedAt;

  const RemoteConfig({
    this.configVersion = 0,
    this.flags = const {},
    this.ui = const {},
    this.update,
    this.issuedAt,
  });

  /// Deserialise from the `config` sub-object in the heartbeat response.
  ///
  /// Expected invocation:
  /// ```dart
  /// final config = RemoteConfig.fromJson(response['config']);
  /// ```
  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      configVersion: json['config_version'] as int? ?? 0,
      flags: Map<String, dynamic>.from(json['flags'] as Map? ?? {}),
      ui: Map<String, dynamic>.from(json['ui'] as Map? ?? {}),
      update: json['force_update'] != null
          ? UpdateManifest.fromJson(
              Map<String, dynamic>.from(json['force_update'] as Map),
            )
          : null,
      issuedAt: json['issued_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'config_version': configVersion,
        'flags': flags,
        'ui': ui,
        if (update != null) 'force_update': update!.toJson(),
        if (issuedAt != null) 'issued_at': issuedAt,
      };

  /// Whether [configVersion] is newer than [lastAppliedVersion], indicating
  /// that this config should be applied (i.e. it is not stale).
  bool isNewerThan(int lastAppliedVersion) =>
      configVersion > lastAppliedVersion;
}
