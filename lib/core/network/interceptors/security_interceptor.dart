import 'package:dio/dio.dart';
import '../../../core/utils/logger.dart';

class SecurityInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      options.headers['X-Platform'] = 'SmartBoard';
      Log.d('[SecurityInterceptor] Platform Headers Attached.');
    } catch (e) {
      Log.e('[SecurityInterceptor] Error attaching security headers: $e');
    }

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 403) {
      final data = err.response?.data;
      final message = data is Map ? (data['message'] ?? data['detail']) : err.message;
      
      Log.e('🚨 [SecurityInterceptor] Security violation: $message');
      
      // In a kiosk app, we might want to alert IT or show a lockdown screen
    }

    return handler.next(err);
  }
}
