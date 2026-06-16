import 'package:dio/dio.dart';

import '../../auth/token_manager.dart';
import '../../errors/auth_exceptions.dart';
import '../../platform/hardware_fingerprint_service.dart';
import '../../utils/logger.dart';

/// Attaches the current Bearer token to every outgoing Dio request and
/// transparently replays requests that receive a 401 response.
///
/// 401 replay:
///   1. Forces a live token rotation via [TokenManager.getValidToken].
///   2. Mutates the failed request's `Authorization` header.
///   3. Spawns an isolated `Dio()` instance (no interceptors) to replay the
///      exact same payload — no infinite recursion possible.
///   4. If the replayed request also fails, the original 401 is propagated
///      to the caller (fail‑closed).
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await TokenManager().getValidToken();
      options.headers['Authorization'] = 'Bearer $token';
    } on NoCredentialsException {
      // Board has not been registered yet — proceed without auth.
      // The server will return 401 and onError will surface it.
      Log.d('[AuthInterceptor] No credentials — skipping auth header.');
    } catch (e) {
      Log.w('[AuthInterceptor] Could not attach token: $e');
    }

    try {
      final deviceId = await HardwareFingerprintService.getDeviceId();
      if (deviceId.isNotEmpty) {
        options.headers['X-Device-ID'] = deviceId;
      }
    } catch (e) {
      Log.e('[AuthInterceptor] Error attaching device ID: $e');
    }

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      Log.w('[AuthInterceptor] 401 caught — attempting token refresh and replay.');

      try {
        final freshToken =
            await TokenManager().getValidToken(forceRefresh: true);

        err.requestOptions.headers['Authorization'] = 'Bearer $freshToken';

        // Fresh Dio instance with no interceptors — guarantees no re‑entry.
        final response = await Dio().fetch(err.requestOptions);

        Log.i('[AuthInterceptor] 401 replay succeeded.');
        return handler.resolve(response);
      } catch (_) {
        // Refresh failed or replayed request also returned 401 — fail closed.
        Log.e('[AuthInterceptor] 401 recovery failed — propagating original error.');
        return handler.reject(err);
      }
    }

    return handler.next(err);
  }
}
