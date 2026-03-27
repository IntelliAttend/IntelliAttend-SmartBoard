import 'dart:convert';
import 'package:http/http.dart' as http;
import 'hardware_fingerprint_service.dart';
import 'time_sync_service.dart';

class ApiService {
  // Connecting to the newly built local Python FastAPI "Brain" server
  static const String baseUrl = 'http://127.0.0.1:8000/v1/board';

  /// Authenticate the SmartBoard and initialize a new attendance session.
  /// Sends the Unbreakable Trio Fingerprint via the X-Board-MAC header.
  static Future<Map<String, dynamic>> initiateSession(String otp) async {
    // Generate the Zero-Trust Hash Identity
    final deviceFingerprint = await HardwareFingerprintService.getWindowsFingerprint();

    // RTT Step 1: Record the exact local time the request leaves the Smart Board (t0)
    final requestSentAt = DateTime.now();

    final response = await http.post(
      Uri.parse('$baseUrl/session/initiate'),
      headers: {
        'Content-Type': 'application/json',
        'X-Board-MAC': deviceFingerprint,
      },
      body: jsonEncode({
        'otp': otp,
      }),
    );

    // RTT Step 2: Record the exact local time the response arrives (t1)
    final responseReceivedAt = DateTime.now();

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      
      // RTT Step 3: Extract the Python absolute time and compute the skew
      if (responseData['data'] != null && responseData['data']['server_time'] != null) {
        final pythonServerTime = DateTime.parse(responseData['data']['server_time']);
        TimeSyncService.synchronizeWithServer(requestSentAt, responseReceivedAt, pythonServerTime);
      }

      return responseData;
    } else {
      throw Exception('Failed to initiate session. Code: ${response.statusCode}, Body: ${response.body}');
    }
  }
}
