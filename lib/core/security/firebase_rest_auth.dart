import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/time_sync_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import 'secure_storage_service.dart';

/// REST-based replacement for the `firebase_auth` plugin's `getIdToken()` and
/// `signInWithCustomToken()` calls. The plugin's Windows native layer fires
/// `AuthStateListener` / `IdTokenListener` callbacks on a worker thread which
/// crashes the Flutter engine (`abort()` in the VC++ runtime). This class
/// avoids the plugin entirely by talking to Google's REST endpoints directly:
///
///   - identitytoolkit.googleapis.com → signInWithCustomToken (one-shot, at
///     registration time).
///   - securetoken.googleapis.com    → refresh_token → new id_token (on
///     demand, before each authenticated server call).
///
/// All tokens are persisted via [SecureStorageService] (DPAPI-protected on
/// Windows) so the kiosk survives restarts without re-running registration.
class FirebaseRestAuth {
  static final http.Client _client = http.Client();

  // 60-second safety margin so we never present a token that's about to expire
  // mid-request (used conceptually in getIdToken's expiry check).

  // ─── Sign-up (auto-provisioning) ─────────────────────────────────────────

  /// Creates a new account via Identity Toolkit `accounts:signUp` and returns
  /// the parsed response (`localId`, `email`, `idToken`, `refreshToken`,
  /// `expiresIn`). Persists ID + refresh tokens so subsequent calls use REST
  /// refresh only.
  static Future<Map<String, dynamic>> signUpWithPassword(
    String email,
    String password,
  ) async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY missing — cannot sign up.');
    }

    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp'
      '?key=$apiKey',
    );

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw _toRestAuthException(response, 'signUp');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresInStr = data['expiresIn'] as String?;
    if (idToken == null || refreshToken == null || expiresInStr == null) {
      throw StateError(
          '[FirebaseRestAuth] Malformed signUp response: $data');
    }
    final expiresIn = int.parse(expiresInStr);
    final expiryMs =
        TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

    await SecureStorageService.storeRefreshToken(refreshToken);
    await SecureStorageService.storeAccessToken(idToken, expiryMs);

    Log.i('[FirebaseRestAuth] Account created and signed in via signUp. '
        'ID token expires in ${expiresIn}s.');
    return data;
  }

  /// Signs in with email + password. All SmartBoard Firebase accounts are
  /// created by the admin panel's provision_board(). If sign-in fails, the
  /// original error is surfaced (auto-provisioning is disabled to prevent
  /// UID mismatches with PostgreSQL).
  static Future<Map<String, dynamic>> signInWithPassword(
    String email,
    String password,
  ) async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY missing — cannot sign in.');
    }

    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword'
      '?key=$apiKey',
    );

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return _handleSignInResponse(response);
    }

    // NOTE: Auto-provisioning via signUp is DISABLED for SmartBoard accounts.
    // Board Firebase users are created by the admin panel's provision_board()
    // which also creates the matching PostgreSQL User record. If signIn fails,
    // auto-provisioning would create a NEW Firebase account with a DIFFERENT uid,
    // causing the server's postgres lookup to fail with 401.
    // The original error is surfaced directly to the user.

    throw _toRestAuthException(response, 'signInWithPassword');
  }

  // ─── Custom-token sign-in ───────────────────────────────────────────

  /// Exchanges a Firebase custom token (issued by the server after successful
  /// hardware binding at `/register/complete`) for a new ID token + refresh
  /// token. This re-binds the Firebase session to the registered hardware,
  /// embedding any custom claims (e.g. `hardware_id`) that the admin backend
  /// placed in the custom token.
  static Future<Map<String, dynamic>> signInWithCustomToken(
    String customToken,
  ) async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY missing — cannot sign in with custom token.');
    }

    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken'
      '?key=$apiKey',
    );

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': customToken,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw _toRestAuthException(response, 'signInWithCustomToken');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresInStr = data['expiresIn'] as String?;
    if (idToken == null || refreshToken == null || expiresInStr == null) {
      throw StateError(
          '[FirebaseRestAuth] Malformed signInWithCustomToken response: $data');
    }
    final expiresIn = int.parse(expiresInStr);
    final expiryMs =
        TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

    await SecureStorageService.storeRefreshToken(refreshToken);
    await SecureStorageService.storeAccessToken(idToken, expiryMs);

    Log.i('[FirebaseRestAuth] Custom-token sign-in complete. '
        'ID token expires in ${expiresIn}s.');
    return data;
  }

  static Future<Map<String, dynamic>> _handleSignInResponse(
    http.Response response,
  ) async {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresInStr = data['expiresIn'] as String?;
    if (idToken == null || refreshToken == null || expiresInStr == null) {
      throw StateError(
          '[FirebaseRestAuth] Malformed signInWithPassword response: $data');
    }
    final expiresIn = int.parse(expiresInStr);
    final expiryMs =
        TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

    await SecureStorageService.storeRefreshToken(refreshToken);
    await SecureStorageService.storeAccessToken(idToken, expiryMs);

    Log.i('[FirebaseRestAuth] Signed in via password. '
        'ID token expires in ${expiresIn}s.');
    return data;
  }

  /// Quick check if auth tokens exist (cached access token or refresh token).
  /// Does NOT make network calls — a local read from SecureStorage only.
  static Future<bool> hasValidToken() async {
    final cached = await SecureStorageService.getValidAccessToken();
    if (cached != null) return true;
    final refresh = await SecureStorageService.getRefreshToken();
    return refresh != null && refresh.isNotEmpty;
  }

  // ─── Token retrieval / refresh ───────────────────────────────────────────

  /// Returns a currently-valid ID token, refreshing via the Secure Token API
  /// if the cached one is missing or within [_expiryMargin] of expiry.
  ///
  /// Returns `null` if there is no refresh token on record (the device has
  /// never signed in, or registration was cleared). Callers should treat
  /// `null` as "no auth available" and either fall back to API-key auth or
  /// reject the call.
  static Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await SecureStorageService.getValidAccessToken();
      if (cached != null) return cached;
    }

    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    return _refreshIdToken(refreshToken);
  }

  static Future<String?> _refreshIdToken(String refreshToken) async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      Log.e('[FirebaseRestAuth] FIREBASE_API_KEY missing — cannot refresh.');
      return null;
    }

    final uri = Uri.parse(
      'https://securetoken.googleapis.com/v1/token?key=$apiKey',
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'grant_type=refresh_token&refresh_token=$refreshToken',
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        Log.w('[FirebaseRestAuth] refresh failed ${response.statusCode}: '
            '${response.body}');
        // 400 invalid_grant means the refresh token is dead — wipe it so the
        // device drops to API-key-only mode instead of looping retries.
        if (response.statusCode == 400) {
          await SecureStorageService.storeRefreshToken('');
        }
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final idToken = data['id_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      final expiresInStr = data['expires_in'] as String?;
      if (idToken == null || expiresInStr == null) {
        Log.e('[FirebaseRestAuth] Malformed refresh response: $data');
        return null;
      }
      final expiresIn = int.parse(expiresInStr);
      final expiryMs =
          TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

      // Google may rotate the refresh token; persist whichever it returned.
      if (newRefresh != null && newRefresh != refreshToken) {
        await SecureStorageService.storeRefreshToken(newRefresh);
      }
      await SecureStorageService.storeAccessToken(idToken, expiryMs);

      return idToken;
    } catch (e) {
      Log.w('[FirebaseRestAuth] refresh error: $e');
      return null;
    }
  }

  /// Forgets the locally cached tokens. Does NOT call any Google REST
  /// endpoint — refresh tokens stay valid server-side until they are revoked
  /// via the server's admin API.
  static Future<void> signOut() async {
    await SecureStorageService.storeRefreshToken('');
    // storeAccessToken with an expired timestamp invalidates the cache.
    await SecureStorageService.storeAccessToken('', 0);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static FirebaseRestAuthException _toRestAuthException(
    http.Response response,
    String operation,
  ) {
    String code = 'UNKNOWN';
    String? message;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final err = data['error'];
      if (err is Map) {
        message = err['message']?.toString();
        code = message ?? code;
      }
    } catch (e) {
      Log.d('[FirebaseRestAuth] Could not parse error body: $e');
    }
    Log.w('[FirebaseRestAuth] $operation ${response.statusCode}: $code');
    return FirebaseRestAuthException(
      operation: operation,
      statusCode: response.statusCode,
      code: code,
      rawBody: response.body,
    );
  }
}

/// Structured error from a `FirebaseRestAuth` call. The [code] is the
/// `error.message` field returned by Identity Toolkit (e.g.
/// `EMAIL_NOT_FOUND`, `INVALID_PASSWORD`, `USER_DISABLED`, `INVALID_LOGIN_CREDENTIALS`).
class FirebaseRestAuthException implements Exception {
  final String operation;
  final int statusCode;
  final String code;
  final String rawBody;

  FirebaseRestAuthException({
    required this.operation,
    required this.statusCode,
    required this.code,
    required this.rawBody,
  });

  @override
  String toString() =>
      'FirebaseRestAuthException($operation, $statusCode, $code)';
}
