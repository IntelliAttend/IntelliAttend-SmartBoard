import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/time_sync_service.dart';
import '../config/app_config.dart';
import '../errors/auth_exceptions.dart';
import '../security/firebase_rest_auth.dart';
import '../security/secure_storage_service.dart';
import '../utils/logger.dart';

/// Auth state for the SmartBoard.
enum AuthState {
  /// Token is valid, requests can proceed.
  authenticated,

  /// No valid token, login screen should be shown.
  unauthenticated,

  /// Token refresh or re-auth is in progress.
  refreshing,
}

/// Bulletproof auth manager for the SmartBoard.
///
/// Guarantees:
///   - [getValidToken] always returns a valid token OR throws
///   - Never silently fails — callers always know if auth is broken
///   - Auto-refreshes tokens 5 minutes before expiry
///   - Shows login screen when credentials are invalid
///   - Supports explicit login with email + password
class TokenManager {
  static TokenManager? _instance;

  factory TokenManager() => _instance ??= TokenManager._();

  TokenManager._();

  // ── Dependencies ──────────────────────────────────────────────────────

  http.Client client = http.Client();

  // ── Auth state ────────────────────────────────────────────────────────

  AuthState _authState = AuthState.unauthenticated;
  AuthState get authState => _authState;

  /// Called when auth state changes. UI listens to this.
  Function(AuthState)? onAuthStateChanged;

  // ── In-memory cache ───────────────────────────────────────────────────

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  DateTime? _tokenExpiryTime;

  static const Duration _buffer = Duration(minutes: 5);

  // ── Auto-refresh timer ────────────────────────────────────────────────

  Timer? _autoRefreshTimer;

  // ── Refresh deduplication ─────────────────────────────────────────────

  Future<String>? _pendingRefreshFuture;

  // ── Public API ────────────────────────────────────────────────────────

  /// Returns a valid Firebase ID token.
  ///
  /// Resolution order:
  ///   1. In-memory cache (unless [forceRefresh] is true).
  ///   2. Token rotation via refresh token.
  ///   3. Hard re-auth with stored credentials.
  ///
  /// **NEVER returns null.** Either returns a valid token or throws.
  /// This ensures callers always know if auth is working.
  Future<String> getValidToken({bool forceRefresh = false}) async {
    // ── 1. Memory cache ─────────────────────────────────────────────────
    if (!forceRefresh && _cachedAccessToken != null && _tokenExpiryTime != null) {
      if (_tokenExpiryTime!.isAfter(TimeSyncService.timeNow.add(_buffer))) {
        return _cachedAccessToken!;
      }
    }

    _setAuthState(AuthState.refreshing);

    // Refresh token from memory or secure storage.
    final refreshToken =
        _cachedRefreshToken ?? await SecureStorageService.getRefreshToken();

    // ── 2. Token rotation ───────────────────────────────────────────────
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _cachedRefreshToken = refreshToken;
      try {
        final token = await _executeDeduplicatedTokenRotation();
        _setAuthState(AuthState.authenticated);
        _startAutoRefresh();
        return token;
      } catch (_) {
        Log.w('[TokenManager] Refresh failed, trying hard re-auth');
      }
    }

    // ── 3. Hard re-auth ─────────────────────────────────────────────────
    try {
      final token = await executeHardReAuth();
      _setAuthState(AuthState.authenticated);
      _startAutoRefresh();
      return token;
    } on NoCredentialsException {
      _setAuthState(AuthState.unauthenticated);
      rethrow;
    } on InvalidCredentialsException {
      _setAuthState(AuthState.unauthenticated);
      rethrow;
    }
  }

  /// Explicit login with email + password.
  ///
  /// Called by the login screen when user enters credentials.
  /// On success, stores credentials and caches token.
  /// Throws [InvalidCredentialsException] on wrong password.
  /// Throws [FirebaseRestAuthException] on other errors.
  Future<String> loginWithCredentials(String email, String password) async {
    _setAuthState(AuthState.refreshing);

    try {
      final data = await FirebaseRestAuth.signInWithPassword(email, password);
      _updateCacheFromSignInData(data);

      // Store credentials for future re-auth
      await SecureStorageService.storeBoardCredentials(email, password);

      _setAuthState(AuthState.authenticated);
      _startAutoRefresh();

      final token = data['idToken'] as String;
      Log.i('[TokenManager] Login successful: $email');
      return token;
    } on FirebaseRestAuthException catch (e) {
      _setAuthState(AuthState.unauthenticated);
      if (e.code == 'EMAIL_NOT_FOUND' || e.code == 'INVALID_LOGIN_CREDENTIALS') {
        throw InvalidCredentialsException();
      }
      rethrow;
    }
  }

  /// Forces a full re-authentication using stored credentials.
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

  /// Check if credentials are stored (board has registered before).
  Future<bool> hasStoredCredentials() async {
    final email = await SecureStorageService.getBoardEmail();
    final password = await SecureStorageService.getBoardPassword();
    return email != null && password != null;
  }

  /// Logout — clears all tokens and credentials.
  Future<void> logout() async {
    _stopAutoRefresh();
    invalidateCache();
    await SecureStorageService.storeRefreshToken('');
    await SecureStorageService.storeAccessToken('', 0);
    _setAuthState(AuthState.unauthenticated);
    Log.i('[TokenManager] Logged out');
  }

  static void resetInstance() {
    _instance = null;
  }

  void invalidateCache() {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _tokenExpiryTime = null;
    _pendingRefreshFuture = null;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _setAuthState(AuthState.unauthenticated);
  }

  // ── Auth state management ─────────────────────────────────────────────

  void _setAuthState(AuthState state) {
    if (_authState != state) {
      _authState = state;
      onAuthStateChanged?.call(state);
      Log.d('[TokenManager] Auth state: $state');
    }
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────

  void _startAutoRefresh() {
    _stopAutoRefresh();
    if (_tokenExpiryTime == null) return;

    // Refresh 5 minutes before expiry
    final refreshAt = _tokenExpiryTime!.subtract(_buffer);
    final delay = refreshAt.difference(TimeSyncService.timeNow);
    if (delay.isNegative) {
      // Already expired, refresh now
      _scheduleRefresh(const Duration(seconds: 5));
    } else {
      _scheduleRefresh(delay);
    }
  }

  void _scheduleRefresh(Duration delay) {
    _autoRefreshTimer = Timer(delay, () async {
      try {
        Log.i('[TokenManager] Auto-refresh triggered');
        await getValidToken(forceRefresh: true);
      } catch (e) {
        Log.w('[TokenManager] Auto-refresh failed: $e');
        _setAuthState(AuthState.unauthenticated);
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  // ── Deduplication wrapper ─────────────────────────────────────────────

  Future<String> _executeDeduplicatedTokenRotation() async {
    if (_pendingRefreshFuture != null) {
      return _pendingRefreshFuture!;
    }

    _pendingRefreshFuture = _refreshAccessToken();
    try {
      return await _pendingRefreshFuture!;
    } finally {
      _pendingRefreshFuture = null;
    }
  }

  // ── Token rotation ────────────────────────────────────────────────────

  Future<String> _refreshAccessToken() async {
    final apiKey = AppConfig.firebaseApiKey;
    if (apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY missing');
    }

    final refreshToken =
        _cachedRefreshToken ?? await SecureStorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token available');
    }

    final uri = Uri.parse(
      'https://securetoken.googleapis.com/v1/token?key=$apiKey',
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
      rethrow;
    } catch (e) {
      rethrow;
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        _cachedRefreshToken = null;
        _cachedAccessToken = null;
        _tokenExpiryTime = null;
        await SecureStorageService.storeRefreshToken('');
      }
      throw Exception('Token refresh failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['id_token'] as String?;
    final newRefresh = data['refresh_token'] as String?;
    final expiresInStr = data['expires_in'] as String?;

    if (idToken == null || expiresInStr == null) {
      throw FormatException('Malformed refresh response');
    }

    final expiresIn = int.parse(expiresInStr);
    final expiryMs =
        TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);

    if (newRefresh != null && newRefresh != refreshToken) {
      _cachedRefreshToken = newRefresh;
      await SecureStorageService.storeRefreshToken(newRefresh);
    }

    await SecureStorageService.storeAccessToken(idToken, expiryMs);

    _cachedAccessToken = idToken;
    _tokenExpiryTime = DateTime.fromMillisecondsSinceEpoch(expiryMs);

    Log.i('[TokenManager] Token refreshed (${expiresIn}s)');
    return idToken;
  }

  // ── Cache helpers ─────────────────────────────────────────────────────

  void _updateCacheFromSignInData(Map<String, dynamic> data) {
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresInStr = data['expiresIn'] as String?;

    if (idToken != null) _cachedAccessToken = idToken;
    if (refreshToken != null) _cachedRefreshToken = refreshToken;
    if (idToken != null && expiresInStr != null) {
      final expiresIn = int.parse(expiresInStr);
      _tokenExpiryTime = TimeSyncService.timeNow.add(Duration(seconds: expiresIn));
    }
  }
}
