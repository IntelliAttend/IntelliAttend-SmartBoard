import 'dart:io';

import '../core/utils/version.dart';
import '../services/time_sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateManifest v2
//
// Carried inside a heartbeat response (or served from a dedicated
// GET /api/v1/board/check-update endpoint) to tell the board that a
// new binary is available.
//
// The manifest answers one question:
//   "Is this update allowed to install on this machine?"
//
// Every field that constrains installability is enforced by ManifestValidator
// before the download begins. The update agent trusts the validator's verdict.
//
// ── Schema ───────────────────────────────────────────────────────────────────
// schemaVersion (int, required)
//   The manifest format version. Clients reject manifests with a schema
//   version they do not understand, preventing silent data loss from
//   forward-incompatible fields.
//
// ── Channel ──────────────────────────────────────────────────────────────────
// channel (String?, default "stable")
//   Release channel: "stable", "beta", "internal", "dev".
//   A stable-channel device never receives a beta or internal manifest.
//   A beta device may receive stable manifests (downgrade protection).
//
// ── Version Range ────────────────────────────────────────────────────────────
// minimumVersion (String, required)
//   The minimum acceptable version. If the board's current version is
//   strictly less than this, an update is needed.
//
// maximumVersion (String?, optional)
//   Upper bound. The board will not auto-update past this version.
//   Useful for pinning to a major line (e.g. "5.999.0" blocks 6.0.0).
//
// ── OS Compatibility ─────────────────────────────────────────────────────────
// minimumOsVersion (String?, optional)
//   Minimum Windows version required, e.g. "10.0.19045" (Win10 22H2).
//   Compared against Platform.version.
//
// ── Expiry ───────────────────────────────────────────────────────────────────
// expiresAt (String?, optional)
//   ISO-8601 timestamp. Manifests are rejected after this time.
//   Prevents stale update notifications from outdated configs.
//
// ── Integrity ────────────────────────────────────────────────────────────────
// sha256 (String?, optional)
//   SHA-256 hex digest of the MSI (64 hex chars). Verified client-side
//   before installation.
//
// signature (String?, optional)
//   HMAC-SHA256 of the manifest payload (all fields except "signature"
//   itself). Enables end-to-end manifest integrity verification.
//   When present, the client verifies before accepting the manifest.
//
// ── Rollout ──────────────────────────────────────────────────────────────────
// rolloutPercentage (int, 0–100)
//   Canary / staged rollout. Board ID hash maps to this range.
//
// force (bool)
//   If true the board must update immediately (blocking overlay).
//
// ─────────────────────────────────────────────────────────────────────────────
class UpdateManifest {
  // ── Schema ─────────────────────────────────────────────────────────────────

  /// Manifest format version. Clients reject unknown schema versions.
  final int schemaVersion;

  // ── Channel ────────────────────────────────────────────────────────────────

  /// Release channel: "stable", "beta", "internal", "dev".
  /// Null defaults to "stable".
  final String? channel;

  // ── Version Range ──────────────────────────────────────────────────────────

  /// The minimum acceptable version (e.g. "5.5.0"). If the board's current
  /// version is strictly less than this, an update is needed.
  final String minimumVersion;

  /// Upper bound version (e.g. "5.999.0"). The board will not auto-update
  /// past this version. Null means no upper bound.
  final String? maximumVersion;

  // ── OS Compatibility ───────────────────────────────────────────────────────

  /// Minimum Windows version required, e.g. "10.0.19045".
  /// Compared against Platform.version. Null means no OS constraint.
  final String? minimumOsVersion;

  // ── Expiry ─────────────────────────────────────────────────────────────────

  /// ISO-8601 timestamp. Manifests are rejected after this time.
  /// Null means the manifest does not expire.
  final String? expiresAt;

  // ── Integrity ──────────────────────────────────────────────────────────────

  /// SHA-256 hex digest of the MSI (64 hex chars). Verified client-side
  /// before installation. If null, hash verification is skipped.
  final String? sha256;

  /// HMAC-SHA256 of the manifest payload. When present, the client verifies
  /// before accepting the manifest as valid.
  final String? signature;

  // ── Payload ────────────────────────────────────────────────────────────────

  /// Full HTTPS URL to the MSI package.
  final String? downloadUrl;

  /// File size in bytes (optional, for download progress UI).
  final int? fileSize;

  /// Human-readable release notes (markdown-ish plain text).
  final String? releaseNotes;

  /// ISO-8601 timestamp of when this manifest was published.
  final String? publishedAt;

  // ── Rollout ────────────────────────────────────────────────────────────────

  /// If true the board must update immediately (blocking overlay). If false
  /// the board may prompt the user or wait for idle time.
  final bool force;

  /// Rollout percentage (0–100). A board maps its stable board ID hash to
  /// this range to decide whether it is in the canary cohort.
  final int rolloutPercentage;

  // ───────────────────────────────────────────────────────────────────────────

  const UpdateManifest({
    this.schemaVersion = 1,
    this.channel,
    required this.minimumVersion,
    this.maximumVersion,
    this.minimumOsVersion,
    this.expiresAt,
    this.downloadUrl,
    this.sha256,
    this.signature,
    this.fileSize,
    this.releaseNotes,
    this.publishedAt,
    this.force = false,
    this.rolloutPercentage = 100,
  });

  // ── Deserialisation ──────────────────────────────────────────────────────

  /// Deserialise from the JSON sub-object returned by the server.
  ///
  /// Expected shape (v2):
  /// ```json
  /// {
  ///   "schema_version": 2,
  ///   "channel": "stable",
  ///   "minimum_version": "5.5.0",
  ///   "maximum_version": "5.999.0",
  ///   "minimum_os_version": "10.0.19045",
  ///   "expires_at": "2026-12-31T23:59:59Z",
  ///   "download_url": "https://cdn.example.com/iasb-5.5.0.msi",
  ///   "sha256": "abc123...",
  ///   "signature": "hmac-of-payload...",
  ///   "file_size": 19437568,
  ///   "force": true,
  ///   "rollout_percentage": 25,
  ///   "release_notes": "Fixed QR crash on rapid scan",
  ///   "published_at": "2026-06-28T12:00:00Z"
  /// }
  /// ```
  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      schemaVersion: _parseInt(json['schema_version'], 1),
      channel: json['channel']?.toString(),
      minimumVersion: json['minimum_version']?.toString() ?? '0.0.0',
      maximumVersion: json['maximum_version']?.toString(),
      minimumOsVersion: json['minimum_os_version']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      downloadUrl: json['download_url']?.toString(),
      sha256: json['sha256']?.toString(),
      signature: json['signature']?.toString(),
      fileSize: _parseIntNullable(json['file_size']),
      releaseNotes: json['release_notes']?.toString(),
      publishedAt: json['published_at']?.toString(),
      force: json['force'] == true,
      rolloutPercentage: _parseInt(json['rollout_percentage'], 100),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (channel != null) 'channel': channel,
        'minimum_version': minimumVersion,
        if (maximumVersion != null) 'maximum_version': maximumVersion,
        if (minimumOsVersion != null) 'minimum_os_version': minimumOsVersion,
        if (expiresAt != null) 'expires_at': expiresAt,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (sha256 != null) 'sha256': sha256,
        if (signature != null) 'signature': signature,
        if (fileSize != null) 'file_size': fileSize,
        'force': force,
        'rollout_percentage': rolloutPercentage,
        if (releaseNotes != null) 'release_notes': releaseNotes,
        if (publishedAt != null) 'published_at': publishedAt,
      };

  // ── Computed Properties ──────────────────────────────────────────────────

  /// The parsed [minimumVersion] to avoid re-parsing on every comparison.
  Version get parsedMinimum {
    try {
      return Version.parse(minimumVersion);
    } catch (_) {
      return Version.zero;
    }
  }

  /// The parsed [maximumVersion]. Returns null if not set or unparseable.
  Version? get parsedMaximum {
    if (maximumVersion == null) return null;
    try {
      return Version.parse(maximumVersion!);
    } catch (_) {
      return null;
    }
  }

  /// Resolved channel name, defaulting to "stable".
  String get resolvedChannel => channel ?? 'stable';

  /// Whether the manifest has expired (expiresAt is in the past).
  bool get isExpired {
    if (expiresAt == null) return false;
    try {
      final expiry = DateTime.parse(expiresAt!);
      return TimeSyncService.timeNow.isAfter(expiry);
    } catch (_) {
      return false;
    }
  }

  /// The current Windows version as reported by the platform, parsed.
  /// Returns (major, minor, build) or null if unavailable.
  static ({int major, int minor, int build})? get currentWindowsVersion {
    if (!_isWindows) return null;
    final versionStr = Platform.version;
    // Platform.version on Windows: "10.0.19045" (Major.Minor.Build)
    return _parseWindowsVersion(versionStr);
  }

  static bool get _isWindows => Platform.isWindows;

  static ({int major, int minor, int build})? _parseWindowsVersion(String version) {
    final parts = version.split('.');
    if (parts.length < 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final build = int.tryParse(parts[2]);
    if (major == null || minor == null || build == null) return null;
    return (major: major, minor: minor, build: build);
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  static int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? _parseIntNullable(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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
