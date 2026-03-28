import 'dart:convert';
import 'package:http/http.dart' as http;
import 'hardware_fingerprint_service.dart';
import 'time_sync_service.dart';

class ApiService {
  // Connecting to the local Python FastAPI "Brain" server
  static const String baseUrl = 'http://127.0.0.1:8000/v1/board';

  /// PHASE 1: One-Time Device Registration.
  /// Binds the hardware fingerprint to a specific classroom in the system.
  static Future<Map<String, dynamic>> registerDevice({
    required String roomId,
    required String roomName,
    String? building,
    String? department,
    int rosterCount = 60,
  }) async {
    final deviceFingerprint = await HardwareFingerprintService.getWindowsFingerprint();

    final response = await http.post(
      Uri.parse('$baseUrl/device/register'),
      headers: {
        'Content-Type': 'application/json',
        'X-Board-MAC': deviceFingerprint,
      },
      body: jsonEncode({
        'room_id': roomId,
        'room_name': roomName,
        'building': building,
        'department': department,
        'roster_count': rosterCount,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Device registration failed. Code: ${response.statusCode}');
    }
  }

  /// PHASE 4: Fetch the current class schedule for this room.
  static Future<Map<String, dynamic>> getCurrentSchedule() async {
    final deviceFingerprint = await HardwareFingerprintService.getWindowsFingerprint();

    final response = await http.get(
      Uri.parse('$baseUrl/schedule/current'),
      headers: {
        'X-Board-MAC': deviceFingerprint,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch schedule. Code: ${response.statusCode}');
    }
  }

  /// PHASE 2: Daily Session Initiation.
  /// Authenticate the SmartBoard and initialize a new attendance session.
  /// Sends the Silicon Signature via the X-Board-MAC header for zero-trust validation.
  static Future<Map<String, dynamic>> initiateSession(String otp) async {
    // Generate the Zero-Trust Hash Identity
    final deviceFingerprint = await HardwareFingerprintService.getWindowsFingerprint();

    // RTT Step 1: Record the exact local time the request leaves (t0)
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
      
      // RTT Step 3: Extract server time and compute clock skew
      if (responseData['data'] != null && responseData['data']['server_time'] != null) {
        final serverTimeStr = responseData['data']['server_time'];
        final pythonServerTime = DateTime.parse(serverTimeStr);
        TimeSyncService.synchronizeWithServer(requestSentAt, responseReceivedAt, pythonServerTime);
      }

      return responseData;
    } else if (response.statusCode == 403) {
      throw Exception('Device Unregistered: This SmartBoard must be registered before use.');
    } else {
      throw Exception('Failed to initiate session. Code: ${response.statusCode}');
    }
  }
}
