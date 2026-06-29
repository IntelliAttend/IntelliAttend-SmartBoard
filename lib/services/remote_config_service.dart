import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/logger.dart';
import '../models/remote_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RemoteConfigService
//
// Singleton service that holds the latest [RemoteConfig] in memory and
// persists it to [SharedPreferences] so that feature flags survive app
// restarts (important for offline resilience — boards that reboot without
// network still respect the last known config).
//
// ── Thread safety ───────────────────────────────────────────────────────────
// All methods are static. The in-memory [_config] and [_lastVersion] are read
// from / written to only on the main isolate (Flutter's UI thread), so no
// synchronisation is needed.
//
// ── Default behaviour ───────────────────────────────────────────────────────
// Every `isFeatureEnabled(key)` call returns `true` (feature is enabled) when
// the server has not set a value for that key. This is a safe default:
// features are on unless explicitly turned off.
// ─────────────────────────────────────────────────────────────────────────────
class RemoteConfigService {
  RemoteConfigService._(); // prevent instantiation

  static RemoteConfig? _config;
  static int _lastVersion = 0;

  // ── Storage keys ──────────────────────────────────────────────────────────

  static const String _storageKey = 'remote_config_cache';
  static const String _versionKey = 'remote_config_version';

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Load the last known config from disk (if any). Call once at app startup
  /// before the first heartbeat completes, so that flags are available
  /// immediately.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final version = prefs.getInt(_versionKey) ?? 0;

      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _config = RemoteConfig.fromJson(json);
        _lastVersion = version;
        Log.d('[RemoteConfig] Restored config v$version from cache');
      }
    } catch (e) {
      Log.w('[RemoteConfig] Failed to restore cached config: $e');
      // Safe to continue — [_config] stays null, all flags default to true.
    }
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  /// Apply a new config received from the server.
  ///
  /// Returns `true` if the config was actually applied (it was newer than the
  /// last applied version), `false` if it was stale and ignored.
  ///
  /// This method:
  ///   1. Checks [RemoteConfig.isNewerThan] to avoid re-applying stale configs.
  ///   2. Replaces the in-memory [_config].
  ///   3. Persists to SharedPreferences so it survives reboot.
  ///   4. Emits a change notification via the [onConfigChanged] stream.
  static Future<bool> applyConfig(RemoteConfig config) async {
    if (!config.isNewerThan(_lastVersion)) {
      Log.d('[RemoteConfig] Config v${config.configVersion} is stale '
          '(last: v$_lastVersion) — ignoring');
      return false;
    }

    _config = config;
    _lastVersion = config.configVersion;

    Log.i('[RemoteConfig] Applied config v${config.configVersion} '
        '(${config.flags.length} flags, ${config.ui.length} UI keys)');

    // Persist to disk (fire-and-forget — failure is non-critical).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(config.toJson()));
      await prefs.setInt(_versionKey, config.configVersion);
    } catch (e) {
      Log.w('[RemoteConfig] Failed to persist config: $e');
    }

    _notify();
    return true;
  }

  // ── Feature flags ─────────────────────────────────────────────────────────

  /// Check whether [feature] is enabled.
  ///
  /// Returns `true` (enabled) when:
  ///   - No config has been received yet.
  ///   - The feature key is absent from the flags map.
  ///   - The feature key is present and its value is truthy (`true`, `1`, `"1"`,
  ///     `"true"` — case-insensitive).
  ///
  /// Returns `false` (disabled) when:
  ///   - The feature key is present and its value is falsy.
  static bool isFeatureEnabled(String feature) {
    if (_config == null) return true; // safe default
    if (!_config!.flags.containsKey(feature)) return true; // absent = enabled
    return _isTruthy(_config!.flags[feature]);
  }

  /// Get a string value from the flags map, or [defaultValue] if absent.
  static String? flagString(String key, {String? defaultValue}) {
    final value = _config?.flags[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  /// Get a numeric value from the flags map, or [defaultValue] if absent.
  static num? flagNumber(String key, {num? defaultValue}) {
    final value = _config?.flags[key];
    if (value == null) return defaultValue;
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // ── UI overrides ──────────────────────────────────────────────────────────

  /// Get a UI label override, or [fallback] if not set.
  ///
  /// Labels are nested inside the `ui` object. Dot-separated keys are
  /// supported for nested access (e.g. `"labels.welcome_text"` resolves to
  /// `ui["labels"]["welcome_text"]`).
  static String? uiString(String key, {String? fallback}) {
    if (_config == null) return fallback;

    final parts = key.split('.');
    dynamic current = _config!.ui;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return fallback;
      }
    }
    if (current is String) return current;
    return current?.toString() ?? fallback;
  }

  // ── Update manifest ───────────────────────────────────────────────────────

  /// The current update manifest from the server, or null if none.
  static UpdateManifest? get updateManifest => _config?.update;

  // ── Change notification ───────────────────────────────────────────────────

  static final _listeners = <VoidCallback>[];

  /// Register a callback invoked whenever the config is updated.
  static void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  /// Remove a previously registered callback.
  static void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  static void _notify() {
    for (final cb in List<VoidCallback>.from(_listeners)) {
      try {
        cb();
      } catch (e) {
        Log.e('[RemoteConfig] Listener error: $e');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Config version for diagnostic / logging.
  static int get appliedVersion => _lastVersion;

  /// The raw flags map (for debugging / admin panel).
  static Map<String, dynamic>? get rawFlags => _config?.flags;

  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      return value == '1' ||
          value.toLowerCase() == 'true' ||
          value.toLowerCase() == 'yes';
    }
    return value != null; // anything non-null is truthy
  }
}

/// Matching signature used by [RemoteConfigService.addListener].
typedef VoidCallback = void Function();
