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
      final errorCode = data is Map ? (data['error_code'] ?? 'UNKNOWN') : 'UNKNOWN';

      Log.e('[SecurityInterceptor] 403 FORBIDDEN: $errorCode — $message');
      Log.e('[SecurityInterceptor] URL: ${err.requestOptions.uri}');
      Log.e('[SecurityInterceptor] Method: ${err.requestOptions.method}');

      // Log the violation for audit — the server already recorded it,
      // but local logging helps with offline debugging on the board.
    }

    return handler.next(err);
  }
}
