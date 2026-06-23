import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/time_sync_service.dart';
import '../config/app_config.dart';
import '../errors/auth_exceptions.dart';
import '../security/firebase_rest_auth.dart';
import '../security/secure_storage_service.dart';
import '../utils/logger.dart';

/// Singleton gateway that is the single source of truth for Firebase ID
/// tokens on the SmartBoard.
///
/// All outbound HTTP calls — whether through `dio` (AuthInterceptor) or
/// `package:http` (ApiService) — MUST obtain their Bearer token via
/// [getValidToken].  This guarantees:
///
///   1. A 5‑minute memory cache avoids redundant secure‑storage reads.
///   2. When the cache is stale the refresh‑token endpoint is called.
///   3. If the refresh token itself is dead, a silent hard re‑auth is
///      attempted with the hardware‑pinned email+password credentials.
///   4. Only when all three layers fail does an exception reach the caller.
///
/// ## Testability
///
/// The [client] field is public so tests can inject a mock `http.Client`:
///
/// ```dart
/// TokenManager().client = MockClient((req) => async { ... });
/// ```
class TokenManager {
  static TokenManager? _instance;

  /// Returns the singleton instance.
  factory TokenManager() => _instance ??= TokenManager._();

  TokenManager._();

  // ── Dependencies (swap for mocking) ─────────────────────────────────────

  /// HTTP client used for calls to `securetoken.googleapis.com`.
  /// NOT pinned — Google rotates certificates frequently.
  http.Client client = http.Client();

  // ── In‑memory cache ─────────────────────────────────────────────────────

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  DateTime? _tokenExpiryTime;

  /// 5‑minute buffer guarantees the token is refreshed before Google rejects
  /// it on systems with reliable NTP.  For clock‑drifted boards, callers
  /// should pass `forceRefresh: true`.
  static const Duration _buffer = Duration(minutes: 5);

  // ── Refresh deduplication ───────────────────────────────────────────────

  /// Non‑null while a token‑rotation HTTP request is in flight.
  /// Subsequent callers multiplex onto the same future instead of firing
  /// parallel requests (thundering‑herd protection).
  Future<String>? _pendingRefreshFuture;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Returns a valid Firebase ID token.
  ///
  /// Resolution order:
  ///   1. In‑memory cache (unless [forceRefresh] is true).
  ///   2. Token rotation via `securetoken.googleapis.com/v1/token`.
  ///   3. Hard re‑auth via `identitytoolkit.googleapis.com/…/signInWithPassword`
  ///      using the hardware‑pinned credentials stored during registration.
  ///
  /// Throws [NoCredentialsException] if no board credentials are stored
  /// (the board has never completed registration).
  ///
  /// Throws [InvalidCredentialsException] if the stored credentials were
  /// rejected by the server (account disabled / password changed).
  Future<String> getValidToken({bool forceRefresh = false}) async {
    // ── 1. Memory cache ─────────────────────────────────────────────────
    if (!forceRefresh && _cachedAccessToken != null && _tokenExpiryTime != null) {
      if (_tokenExpiryTime!.isAfter(DateTime.now().add(_buffer))) {
        return _cachedAccessToken!;
      }
    }

    // Refresh token from memory or secure storage.
    final refreshToken =
        _cachedRefreshToken ?? await SecureStorageService.getRefreshToken();

    // ── 2. Token rotation ───────────────────────────────────────────────
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _cachedRefreshToken = refreshToken;
      try {
        return await _executeDeduplicatedTokenRotation();
      } catch (_) {
        // Fall through to hard re‑auth
      }
    }

    // ── 3. Hard re‑auth ─────────────────────────────────────────────────
    return await executeHardReAuth();
  }

  /// Forces a full re‑authentication using the hardware‑pinned email and
  /// password stored during board registration.
  ///
  /// On success the new ID token is cached both in memory and in secure
  /// storage, and the (possibly rotated) refresh token is persisted.
  ///
  /// Throws [NoCredentialsException] or [InvalidCredentialsException].
  Future<String> executeHardReAuth() async {
    final email = await SecureStorageService.getBoardEmail();
    final password = await SecureStorageService.getBoardPassword();

    if (email == null || password == null) {
      throw NoCredentialsException();
    }

    try {
      final data = await FirebaseRestAuth.signInWithPassword(email, password);
      _updateCacheFromSignInData(data);
      return data['idToken'] as String;
    } on FirebaseRestAuthException {
      throw InvalidCredentialsException();
    }
  }

  /// Resets the singleton so the next call to `TokenManager()` creates a
  /// fresh instance with no memory cache.  Intended for testing only.
  static void resetInstance() {
    _instance = null;
  }

  /// Clears all cached tokens.  The next call to [getValidToken] will go
  /// through the full resolution chain.  Does NOT wipe secure storage.
  void invalidateCache() {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _tokenExpiryTime = null;
    _pendingRefreshFuture = null;
  }

  // ── Deduplication wrapper ───────────────────────────────────────────────

  Future<String> _executeDeduplicatedTokenRotation() async {
    // If a rotation is already in flight, join it.
    if (_pendingRefreshFuture != null) {
      return _pendingRefreshFuture!;
    }

    _pendingRefreshFuture = _refreshAccessToken();
    try {
      return await _pendingRefreshFuture!;
    } finally {
      // CRITICAL: Clear even on exception so a transient network drop never
      // permanently poisons the pipeline.
      _pendingRefreshFuture = null;
    }
  }

  // ── Token rotation ──────────────────────────────────────────────────────

  /// POSTs the refresh token to `securetoken.googleapis.com/v1/token` and
  /// persists the new ID + (rotated) refresh tokens.
  ///
  /// Throws if the HTTP call fails or the response is malformed.
  Future<String> _refreshAccessToken() async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY missing — cannot refresh token.');
    }

    final refreshToken =
        _cachedRefreshToken ?? await SecureStorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token available for rotation.');
    }

    final uri = Uri.parse(
      'https://securetoken.googleapis.com/v1/token'
      '?key=$apiKey',
    );

    http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=refresh_token&refresh_token=$refreshToken',
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      Log.w('[TokenManager] Refresh timed out.');
      rethrow;
    } catch (e) {
      Log.w('[TokenManager] Refresh network error: $e');
      rethrow;
    }

    if (response.statusCode != 200) {
      Log.w('[TokenManager] Refresh failed ${response.statusCode}: ${response.body}');

      // 400 with "invalid_grant" means the refresh token was revoked/expired.
      if (response.statusCode == 400) {
        _cachedRefreshToken = null;
        _cachedAccessToken = null;
        _tokenExpiryTime = null;
        await SecureStorageService.storeRefreshToken('');
      }

      throw Exception('Token refresh failed (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['id_token'] as String?;
    final newRefresh = data['refresh_token'] as String?;
    final expiresInStr = data['expires_in'] as String?;

    if (idToken == null || expiresInStr == null) {
      throw FormatException('Malformed refresh response: $data');
    }

    final expiresIn = int.parse(expiresInStr);
    final expiryMs =
        TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

    // Google may rotate the refresh token; persist whatever it returned.
    if (newRefresh != null && newRefresh != refreshToken) {
      _cachedRefreshToken = newRefresh;
      await SecureStorageService.storeRefreshToken(newRefresh);
    }

    await SecureStorageService.storeAccessToken(idToken, expiryMs);

    _cachedAccessToken = idToken;
    _tokenExpiryTime = DateTime.fromMillisecondsSinceEpoch(expiryMs);

    if (kDebugMode) {
      debugPrint('[TokenManager] Token refreshed (expires in ${expiresIn}s).');
    }

    return idToken;
  }

  // ── Cache helpers ───────────────────────────────────────────────────────

  void _updateCacheFromSignInData(Map<String, dynamic> data) {
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresInStr = data['expiresIn'] as String?;

    if (idToken != null) {
      _cachedAccessToken = idToken;
    }
    if (refreshToken != null) {
      _cachedRefreshToken = refreshToken;
    }
    if (idToken != null && expiresInStr != null) {
      final expiresIn = int.parse(expiresInStr);
      _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn));
    }
  }
}
