import 'package:dio/dio.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/utils/logger.dart';

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await SecureStorageService.getValidAccessToken();
      
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
        Log.d('[AuthInterceptor] Attached Access Token to ${options.path}');
      } else {
        Log.w('[AuthInterceptor] No valid Access Token found for ${options.path}');
      }
      
      // Inject Hardware ID for device tracking
      final deviceId = await SecureStorageService.getApiKey(); // Using API Key slot for basic ID or HardwareID
      if (deviceId != null) {
        options.headers['X-Device-ID'] = deviceId;
      }
      
    } catch (e) {
      Log.e('[AuthInterceptor] Error attaching auth headers: $e');
    }
    
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Handle 401 Unauthorized by attempting to refresh token
    if (err.response?.statusCode == 401) {
      Log.w('[AuthInterceptor] 401 Unauthorized detected. Attempting token refresh...');
      
      // This logic would normally be implemented in an AuthRepository and called here
      // For now, we follow the mobile app's pattern of centralized refresh
    }
    
    return handler.next(err);
  }
}
