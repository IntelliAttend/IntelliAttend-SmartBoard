/// Immutable semantic version value object.
///
/// Parses strings in `major.minor.patch` or `major.minor.patch+build` format
/// and supports comparison operators. Used by [AutoUpdater] to decide whether
/// the installed version is older than the server's minimum version.
///
/// Grammar:
///   version-string = digits "." digits "." digits ["+" digits]
///
/// Examples: `5.4.0`, `5.4.0+1`, `2.0.0-beta` (pre-release tags are ignored
/// for comparison — only major/minor/patch participate).
class Version implements Comparable<Version> {
  final int major;
  final int minor;
  final int patch;
  final String? buildNumber;
  final String? preRelease;

  const Version({
    required this.major,
    required this.minor,
    required this.patch,
    this.buildNumber,
    this.preRelease,
  });

  /// Parses [raw] into a [Version].
  ///
  /// Acceptable inputs:
  ///   - `"5.4.0"`          → Version(5, 4, 0)
  ///   - `"5.4.0+1"`        → Version(5, 4, 0, buildNumber: "1")
  ///   - `"5.4.0-beta"`     → Version(5, 4, 0, preRelease: "beta")
  ///   - `"5.4.0-beta+1"`   → Version(5, 4, 0, preRelease: "beta", buildNumber: "1")
  ///
  /// Throws [FormatException] if the string does not match `X.Y.Z` at minimum.
  factory Version.parse(String raw) {
    final stripped = raw.trim();

    // Extract the pre-release tag if present (e.g. "5.4.0-beta").
    String? preRelease;
    final preReleaseIdx = stripped.indexOf('-');
    String semverPart;
    if (preReleaseIdx >= 0) {
      preRelease = stripped.substring(preReleaseIdx + 1);
      semverPart = stripped.substring(0, preReleaseIdx);
    } else {
      semverPart = stripped;
    }

    // Extract the build number after '+' if present.
    String? buildNumber;
    final buildIdx = semverPart.indexOf('+');
    String versionCore;
    if (buildIdx >= 0) {
      buildNumber = semverPart.substring(buildIdx + 1);
      versionCore = semverPart.substring(0, buildIdx);
    } else {
      versionCore = semverPart;
    }

    final parts = versionCore.split('.');
    if (parts.length < 3) {
      throw FormatException('Version must have at least major.minor.patch', raw);
    }

    return Version(
      major: int.parse(parts[0]),
      minor: int.parse(parts[1]),
      patch: int.parse(parts[2]),
      buildNumber: buildNumber,
      preRelease: preRelease,
    );
  }

  /// Convenience constructor for "0.0.0" (uninitialised / unknown).
  static const zero = Version(major: 0, minor: 0, patch: 0);

  // ── Comparison ────────────────────────────────────────────────────────────

  @override
  int compareTo(Version other) {
    final majorCmp = major.compareTo(other.major);
    if (majorCmp != 0) return majorCmp;
    final minorCmp = minor.compareTo(other.minor);
    if (minorCmp != 0) return minorCmp;
    return patch.compareTo(other.patch);
  }

  /// True when [other] has the same major.minor.patch (build & pre-release
  /// are ignored for equivalence — use [identicalBuild] for exact match).
  @override
  bool operator ==(Object other) =>
      other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  bool operator <(Version other) => compareTo(other) < 0;
  bool operator <=(Version other) => compareTo(other) <= 0;
  bool operator >(Version other) => compareTo(other) > 0;
  bool operator >=(Version other) => compareTo(other) >= 0;

  /// True when build numbers are also equal (or both null).
  bool identicalBuild(Version other) =>
      this == other && buildNumber == other.buildNumber;

  // ── Formatting ────────────────────────────────────────────────────────────

  @override
  String toString() {
    final buf = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) buf.write('-$preRelease');
    if (buildNumber != null) buf.write('+$buildNumber');
    return buf.toString();
  }

  /// Shorthand "X.Y.Z" without pre-release or build suffix.
  String get semantic => '$major.$minor.$patch';
}
