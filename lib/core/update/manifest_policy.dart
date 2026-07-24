// ─────────────────────────────────────────────────────────────────────────────
// ManifestPolicy
//
// Declares the deployment constraints that a board enforces when evaluating
// an UpdateManifest. The policy is constructed once at startup and passed
// to ManifestValidator.check().
//
// The policy answers: "Given this board's identity and environment, what
// manifest fields are we willing to accept?"
//
// Design notes:
//   - All fields are nullable. A null field means "no constraint."
//   - The policy is immutable after construction.
//   - The policy does NOT know about rollout logic (that lives in the
//     manifest's includesBoard). It only checks policy constraints.
// ─────────────────────────────────────────────────────────────────────────────
class ManifestPolicy {
  /// Accepted schema versions. If null, any schema version is accepted.
  /// If non-null, only schemas in this set are allowed.
  ///
  /// Rationale: the client should reject manifests whose format it does not
  /// understand, preventing silent data loss from forward-incompatible fields.
  final Set<int>? acceptedSchemaVersions;

  /// The release channel this board is assigned to (e.g. "stable", "beta").
  /// Manifests targeting a different channel are rejected unless the board
  /// is explicitly allowed to receive cross-channel updates.
  final String boardChannel;

  /// Additional channels this board may receive (beyond [boardChannel]).
  /// For example, a "stable" board with allowedChannels={"stable","internal"}
  /// will accept internal manifests but reject "beta" manifests.
  final Set<String>? allowedChannels;

  /// Current Windows version as (major, minor, build). The validator compares
  /// this against the manifest's minimumOsVersion.
  final ({int major, int minor, int build})? windowsVersion;

  /// The currently installed application version. Used for version-range
  /// validation and downgrade detection.
  final String installedVersion;

  /// The board's unique identifier. Used for rollout cohort checks.
  final String boardId;

  /// HMAC-SHA256 secret key for verifying manifest signatures.
  /// Null means signature verification is disabled (not recommended
  /// for production).
  final String? hmacSecretKey;

  const ManifestPolicy({
    this.acceptedSchemaVersions,
    this.boardChannel = 'stable',
    this.allowedChannels,
    this.windowsVersion,
    required this.installedVersion,
    required this.boardId,
    this.hmacSecretKey,
  });

  /// Whether the given channel is acceptable for this board.
  bool isChannelAllowed(String channel) {
    if (channel == boardChannel) return true;
    if (allowedChannels != null && allowedChannels!.contains(channel)) return true;
    return false;
  }
}
