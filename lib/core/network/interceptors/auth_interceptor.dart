import 'package:dio/dio.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/platform/hardware_fingerprint_service.dart';
import '../../../core/utils/logger.dart';
import '../../../services/time_sync_service.dart';

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await SecureStorageService.getValidAccessToken();
      
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
        Log.d('[AuthInterceptor] Attached Access Token to ${options.path}');
      }
      
      // Strict Hardware Binding: Every request must carry the physical device ID
      final deviceId = await HardwareFingerprintService.getDeviceId();
      if (deviceId.isNotEmpty) {
        options.headers['X-Device-ID'] = deviceId;
      }
      
    } catch (e) {
      Log.e('[AuthInterceptor] Error attaching auth headers: $e');
    }
    
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // v5.4 Strategy: Handle 401 Unauthorized by attempting a silent JWT refresh
    if (err.response?.statusCode == 401) {
      final refreshToken = await SecureStorageService.getRefreshToken();
      
      if (refreshToken != null && refreshToken.isNotEmpty) {
        Log.i('[AuthInterceptor] 401 Unauthorized detected. Attempting JWT rotation...');
        
        try {
          // 1. Request new access token from backend
          // We use a fresh Dio instance to avoid recursive interceptor loops
          final refreshDio = Dio(BaseOptions(baseUrl: err.requestOptions.baseUrl));
          final response = await refreshDio.post(
            '/api/v1/device/register/token/refresh',
            options: Options(headers: {'X-Refresh-Token': refreshToken}),
          );

          if (response.statusCode == 200) {
            final data = response.data as Map<String, dynamic>;
            final newAccessToken = data['access_token']?.toString();
            final expiresIn = data['expires_in'] as int? ?? 3600;

            if (newAccessToken != null) {
              // 2. Persist new token
              final expiryMs = TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);
              await SecureStorageService.storeAccessToken(newAccessToken, expiryMs);
              
              Log.i('[AuthInterceptor] JWT rotation successful. Retrying original request...');

              // 3. Update headers and retry original request
              final options = err.requestOptions;
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              
              final retryResponse = await refreshDio.fetch(options);
              return handler.resolve(retryResponse);
            }
          }
        } catch (refreshError) {
          Log.e('[AuthInterceptor] JWT rotation failed: $refreshError');
          // If refresh fails, we might want to clear tokens to force re-registration
          // but for now we just let the error propagate.
        }
      } else {
        Log.w('[AuthInterceptor] 401 Unauthorized but no refresh token available.');
      }
    }
    
    return handler.next(err);
  }
}
