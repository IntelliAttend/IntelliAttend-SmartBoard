import 'package:dio/dio.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/platform/hardware_fingerprint_service.dart';
import '../../../core/utils/logger.dart';

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
    // Token refresh endpoint removed — 401 errors propagate as-is
    return handler.next(err);
  }
}
