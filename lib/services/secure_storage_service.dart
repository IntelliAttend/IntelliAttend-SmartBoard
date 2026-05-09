import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/utils/logger.dart';

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
  static const String _keyClockSkew = 'clock_skew_ms';
  static const String _keyIdleTheme = 'idle_break_theme'; // 'white' or 'dark'
  static const String _keyRegToken = 'registration_token';

  // Android: encrypted SharedPreferences (Android Keystore).
  // iOS / macOS: Keychain (kSecClassGenericPassword, after-first-unlock).
  // Windows: DPAPI per-user.
  // Linux: libsecret / Secret Service.
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> init() async {
    // v6.3: SharedPreferences fallback removed for security hardening.
  }

  static Future<void> _write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      Log.e('🚨 [SecureStorage] FATAL: OS Keychain Write Failure ($e). Session data at risk.');
      // v6.3: Disable silent fallback to plaintext SharedPreferences.
      // If the hardware keychain is broken, we cannot trust the storage.
      rethrow;
    }
  }

  static Future<String?> _read(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (e) {
      Log.e('🚨 [SecureStorage] FATAL: OS Keychain Read Failure ($e).');
      rethrow;
    }
  }

  static Future<void> _delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (e) {
      Log.e('🚨 [SecureStorage] FATAL: OS Keychain Delete Failure ($e).');
      rethrow;
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
  // Clock Skew (Time Drift Offset)
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> storeClockSkew(int skewMs) => 
      _write(_keyClockSkew, skewMs.toString());

  static Future<int?> getClockSkew() async {
    final val = await _read(_keyClockSkew);
    return val != null ? int.tryParse(val) : null;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Registration Flow (AUDIT-L1)
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> storeRegistrationToken(String token) => _write(_keyRegToken, token);
  static Future<String?> getRegistrationToken() => _read(_keyRegToken);
  static Future<void> clearRegistrationToken() => _delete(_keyRegToken);

  // ─────────────────────────────────────────────────────────────────────
  // Bulk wipe — used by registration reset and tamper-detection paths.
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> clearAll() async {
    await _delete(_keyApiKey);
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
    await _delete(_keyTokenExpiry);
    // SEC-3 FIX: Also wipe keys added in v6.3 — stale skew or a dangling
    // registration token could confuse the next registration flow on this device.
    await _delete(_keyClockSkew);
    await _delete(_keyRegToken);
    await _delete(_keyIdleTheme);
    // Note: session_secret_* keys are keyed by dynamic sessionId.
    // Callers that end a session should call clearSessionSecret(sessionId).
    // For a nuclear wipe, use _secure.deleteAll() — but that risks clearing
    // unrelated OS-level keys on shared keychains.
  }
}
