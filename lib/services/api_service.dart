import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/utils/logger.dart';
import 'hardware_fingerprint_service.dart';
import 'time_sync_service.dart';
import 'secure_storage_service.dart';

class ApiService {
  static const String _defaultBaseUrl = 'https://api-dev.balaseetharamanjaneyulu.com';

  // ─── URL Resolution ───────────────────────────────────────────────────────

  static Future<String> _resolveBaseUrl() async {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;

    try {
      final overrideFile = File('server_override.txt');
      if (await overrideFile.exists()) {
        final content = (await overrideFile.readAsString()).trim();
        if (content.isNotEmpty) return content;
      }
    } catch (e) {
      Log.w('Override file error: $e');
    }

    return _defaultBaseUrl;
  }

  /// Build a URI from a path segment, normalizing double slashes.
  static Future<Uri> _buildUri(String path) async {
    final base = await _resolveBaseUrl();
    final baseUri = Uri.parse(base);
    final cleanPath = '/${path.replaceAll(RegExp(r'/+'), '/')}'.replaceFirst(RegExp(r'^//+'), '/');
    return baseUri.replace(path: cleanPath);
  }

  // ─── Authentication ───────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    String? token = await SecureStorageService.getValidAccessToken();
    token ??= await _refreshToken();

    if (token != null) {
      return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
    }

    final apiKey = await SecureStorageService.getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      return {'Content-Type': 'application/json', 'X-API-Key': apiKey};
    }

    final deviceId = await HardwareFingerprintService.getWindowsFingerprint();
    if (deviceId.isNotEmpty && deviceId != 'null') {
      return {'Content-Type': 'application/json', 'X-Device-ID': deviceId};
    }

    return {'Content-Type': 'application/json'};
  }

  static Future<String?> _refreshToken() async {
    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final uri = await _buildUri('api/v1/board/auth/refresh');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newToken = data['access_token']?.toString();
        if (newToken != null) {
          final expiresAt = data['expires_in'] is int
              ? DateTime.now().millisecondsSinceEpoch + (data['expires_in'] as int) * 1000
              : DateTime.now().millisecondsSinceEpoch + 900000;
          await SecureStorageService.storeAccessToken(newToken, expiresAt);
          Log.i('Access token refreshed');
          return newToken;
        }
      }
    } catch (e) {
      Log.e('Token refresh failed: $e');
    }
    return null;
  }

  // ─── Registration Flow ────────────────────────────────────────────────────

  static Future<void> requestRegistrationOtp({required String roomId}) async {
    final uri = await _buildUri('api/v1/board/register/request-otp');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'classroom_id': roomId}),
    );

    if (response.statusCode != 200) {
      throw _apiError('OTP request', response);
    }
  }

  static Future<Map<String, dynamic>> verifyRegistrationOtp({
    required String roomId,
    required String otp,
    String? deviceName,
  }) async {
    final hardwareId = await HardwareFingerprintService.getWindowsFingerprint();
    final uri = await _buildUri('api/v1/board/register');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'classroom_id': roomId,
        'otp': otp,
        'hardware_fingerprint': hardwareId,
        'device_name': deviceName ?? 'SmartBoard $roomId',
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _apiError('Registration verification', response);
  }

  // ─── Time & Context ───────────────────────────────────────────────────────

  static Future<int> syncTime() async {
    final uri = await _buildUri('api/v1/board/time');
    final clientSent = DateTime.now().millisecondsSinceEpoch;

    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode != 200) throw _apiError('Time sync', response);

    final data = jsonDecode(response.body);
    final dynamic payload = data['data'] ?? data;
    final serverTs = payload['server_timestamp_ms'] is int
        ? payload['server_timestamp_ms']
        : DateTime.now().millisecondsSinceEpoch;

    final clientReceived = DateTime.now().millisecondsSinceEpoch;
    final rtt = clientReceived - clientSent;
    final skew = serverTs - (clientReceived - (rtt ~/ 2));
    TimeSyncService.setSkew(skew);

    return serverTs;
  }

  static Future<Map<String, dynamic>> syncContext() async {
    final uri = await _buildUri('api/v1/board/sync-context');
    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode != 200) throw _apiError('Context sync', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ─── Session Operations ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> initiateSession(String otp) async {
    final uri = await _buildUri('api/v1/board/session/initiate');
    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'otp': otp}),
    );

    if (response.statusCode != 200) throw _apiError('Session initiation', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> recordLiveAttendance({
    required String studentId,
    required String sessionId,
    required String roomId,
    required String entryType,
  }) async {
    final uri = await _buildUri('api/v1/board/session/attendance/record-live');
    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'student_id': studentId,
        'session_id': sessionId,
        'room_id': roomId,
        'entry_type': entryType,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (response.statusCode != 200) throw _apiError('Live attendance', response);
  }

  static Future<void> syncVault({
    required String sessionId,
    required List<Map<String, dynamic>> queuedScans,
  }) async {
    final uri = await _buildUri('api/v1/board/sync/vault');
    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'queued_scans': queuedScans,
      }),
    );

    if (response.statusCode != 200) throw _apiError('Vault sync', response);
  }

  static Future<void> terminateSession(String sessionId) async {
    final uri = await _buildUri('api/v1/board/session/terminate');
    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'session_id': sessionId}),
    );

    if (response.statusCode != 200) throw _apiError('Session termination', response);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static Exception _apiError(String operation, http.Response response) {
    return Exception('$operation failed: ${response.statusCode}\n${response.body}');
  }
}
