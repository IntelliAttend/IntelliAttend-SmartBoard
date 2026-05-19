import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';

class SecureStorageService {
  static const String _keyApiKey = 'api_key';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyAccessToken = 'access_token';
  static const String _keyTokenExpiry = 'token_expiry';
  static const String _keyClockSkew = 'clock_skew_ms';
  static const String _keyClockSkewTimestamp = 'clock_skew_synced_at';
  static const String _keyIdleTheme = 'idle_break_theme';
  static const String _keyRegToken = 'registration_token';
  static const String _keyIsarEncrypt = 'isar_encrypt_key';
  static const String _keyBoardEmail = 'board_email';
  static const String _keyBoardPassword = 'board_password';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> init() async {}

  static Future<void> _write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      Log.e('🚨 [SecureStorage] FATAL: OS Keychain Write Failure ($e). Session data at risk.');
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

  static Future<void> storeApiKey(String apiKey) => _write(_keyApiKey, apiKey);
  static Future<String?> getApiKey() => _read(_keyApiKey);

  static Future<void> storeAccessToken(String token, int expiryMs) async {
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

  static Future<void> storeIdleTheme(String theme) => _write(_keyIdleTheme, theme);
  static Future<String?> getIdleTheme() => _read(_keyIdleTheme);

  static Future<void> storeClockSkew(int skewMs) =>
      _write(_keyClockSkew, skewMs.toString());
  static Future<int?> getClockSkew() async {
    final val = await _read(_keyClockSkew);
    return val != null ? int.tryParse(val) : null;
  }

  static Future<void> storeClockSkewTimestamp(int timestampMs) =>
      _write(_keyClockSkewTimestamp, timestampMs.toString());
  static Future<int?> getClockSkewTimestamp() async {
    final val = await _read(_keyClockSkewTimestamp);
    return val != null ? int.tryParse(val) : null;
  }

  static Future<void> storeRegistrationToken(String token) => _write(_keyRegToken, token);
  static Future<String?> getRegistrationToken() => _read(_keyRegToken);
  static Future<void> clearRegistrationToken() => _delete(_keyRegToken);

  static Future<void> storeIsarEncryptKey(String key) => _write(_keyIsarEncrypt, key);
  static Future<String?> getIsarEncryptKey() => _read(_keyIsarEncrypt);

  // Board Firebase credentials — stored after successful registration so the
  // Firebase plugin can sign in on subsequent boots and use .snapshots() streams.
  static Future<void> storeBoardCredentials(String email, String password) async {
    await _write(_keyBoardEmail, email);
    await _write(_keyBoardPassword, password);
    Log.i('[SecureStorage] Board credentials stored for plugin auth.');
  }

  static Future<String?> getBoardEmail() => _read(_keyBoardEmail);
  static Future<String?> getBoardPassword() => _read(_keyBoardPassword);

  static Future<void> clearBoardCredentials() async {
    await _delete(_keyBoardEmail);
    await _delete(_keyBoardPassword);
  }

  static Future<void> clearAll() async {
    await _delete(_keyApiKey);
    await _delete(_keyAccessToken);
    await _delete(_keyRefreshToken);
    await _delete(_keyTokenExpiry);
    await _delete(_keyClockSkew);
    await _delete(_keyClockSkewTimestamp);
    await _delete(_keyRegToken);
    await _delete(_keyIdleTheme);
    await _delete(_keyIsarEncrypt);
    await _delete(_keyBoardEmail);
    await _delete(_keyBoardPassword);
  }
}
