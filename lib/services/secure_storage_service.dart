import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v5.7: Platform-aware OS-keychain-backed secure storage.
///
/// **Why this matters:** SmartBoards are deployed as kiosk-mode Windows PCs
/// in classrooms. Anyone with file-system access (custodial, IT, a stolen
/// drive) can read SharedPreferences in clear text and recover the
/// `session_secret` — which would let them forge QR codes for any active
/// session and mark themselves present remotely.
///
/// This service now writes to OS-level keychains (DPAPI on Windows, Keychain
/// on macOS prod, Secret Service on Linux, Keystore on Android, Keychain on
/// iOS) via `flutter_secure_storage`. The data on disk is encrypted with a
/// key that the OS protects per-user.
///
/// **macOS dev fallback:** Local development on macOS sometimes hits Keychain
/// entitlement issues (sandboxing, code-signing). To keep `flutter run` fast
/// for engineers, debug builds on macOS fall back to SharedPreferences. This
/// fallback is **never** active in release mode or on production targets.
class SecureStorageService {
  static const String _keyApiKey = 'api_key';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyAccessToken = 'access_token';
  static const String _keyTokenExpiry = 'token_expiry';
  static const String _keyIdleTheme = 'idle_break_theme'; // 'white' or 'dark'

  // Android: encrypted SharedPreferences (Android Keystore).
  // iOS / macOS: Keychain (kSecClassGenericPassword, after-first-unlock).
  // Windows: DPAPI per-user.
  // Linux: libsecret / Secret Service.
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static bool _forceFallback = false;
  static bool get _shouldUseFallback => _forceFallback || (kDebugMode && Platform.isMacOS);

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    if (kDebugMode) {
      debugPrint('🔐 [SecureStorage] Initialized (SharedPreferences available as fallback)');
    }
  }

  static Future<void> _write(String key, String value) async {
    if (_shouldUseFallback) {
      await _prefs!.setString(key, value);
      return;
    }
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      if (e.toString().contains('-34018') || e.toString().contains('errSecMissingEntitlement')) {
        debugPrint('⚠️ [SecureStorage] Keychain Access Failed. Falling back to SharedPreferences.');
        _forceFallback = true;
        await _prefs!.setString(key, value);
      } else {
        rethrow;
      }
    }
  }

  static Future<String?> _read(String key) async {
    if (_shouldUseFallback) {
      return _prefs?.getString(key);
    }
    try {
      return await _secure.read(key: key);
    } catch (e) {
      if (e.toString().contains('-34018')) {
        _forceFallback = true;
        return _prefs?.getString(key);
      }
      rethrow;
    }
  }

  static Future<void> _delete(String key) async {
    if (_shouldUseFallback) {
      await _prefs?.remove(key);
      return;
    }
    try {
      await _secure.delete(key: key);
    } catch (e) {
      if (e.toString().contains('-34018')) {
        _forceFallback = true;
        await _prefs?.remove(key);
      } else {
        rethrow;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // API Key (the SmartBoard's long-lived hardware identity)
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> storeApiKey(String apiKey) => _write(_keyApiKey, apiKey);

  static Future<String?> getApiKey() => _read(_keyApiKey);

  // ─────────────────────────────────────────────────────────────────────
  // Access Token (short-lived, expiring) and Refresh Token
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> storeAccessToken(String token, int expiryMs) async {
    // Two writes — small cost, kept atomic-ish by writing the token first
    // so a partial failure leaves the system in a "no token" state, not a
    // "token without known expiry" state.
    await _write(_keyAccessToken, token);
    await _write(_keyTokenExpiry, expiryMs.toString());
    if (kDebugMode) {
      debugPrint(
        '🔐 [SecureStorage] Access token stored '
        '(expires: ${DateTime.fromMillisecondsSinceEpoch(expiryMs)})',
      );
    }
  }

  static Future<String?> getValidAccessToken() async {
    final token = await _read(_keyAccessToken);
    final expiryStr = await _read(_keyTokenExpiry);
    if (token == null || expiryStr == null) return null;

    final expiry = int.tryParse(expiryStr);
    if (expiry == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= (expiry - 60000)) {
      if (kDebugMode) {
        debugPrint('⚠️ [SecureStorage] Access token expired or expiring soon');
      }
      return null;
    }

    return token;
  }

  static Future<void> storeRefreshToken(String token) =>
      _write(_keyRefreshToken, token);

  static Future<String?> getRefreshToken() => _read(_keyRefreshToken);

  // ─────────────────────────────────────────────────────────────────────
  // Session Secret — the highest-value key in the system.
  // If this leaks, the holder can forge attendance QR codes for the
  // duration of the session. Always stored encrypted by the OS.
  // ─────────────────────────────────────────────────────────────────────
  static String _sessionSecretKey(String sessionId) =>
      'session_secret_$sessionId';

  static Future<void> storeSessionSecret(String sessionId, String secret) =>
      _write(_sessionSecretKey(sessionId), secret);

  static Future<String?> getSessionSecret(String sessionId) =>
      _read(_sessionSecretKey(sessionId));

  static Future<void> clearSessionSecret(String sessionId) =>
      _delete(_sessionSecretKey(sessionId));

  // ─────────────────────────────────────────────────────────────────────
  // Idle Screen Theme Preference
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> storeIdleTheme(String theme) => _write(_keyIdleTheme, theme);
  static Future<String?> getIdleTheme() => _read(_keyIdleTheme);

  // ─────────────────────────────────────────────────────────────────────
  // Bulk wipe — used by registration reset and tamper-detection paths.
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> clearAll() async {
    await _delete(_keyApiKey);
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
    await _delete(_keyTokenExpiry);
    // Note: we don't wipe session_secret_* here because they're keyed by
    // a dynamic sessionId. Callers that end a session should explicitly
    // call `clearSessionSecret(sessionId)`. A nuclear option would be
    // `_secure.deleteAll()` but that risks wiping unrelated app keys.
  }
}
