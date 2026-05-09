import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'hardware_fingerprint_service.dart';

class TelemetryService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  /// The local Python API endpoint for heartbeats.
  static String get _localApiUrl => 
      dotenv.env['LOCAL_API_URL'] ?? 'http://127.0.0.1:8000/v1/board/telemetry';

  /// Collects and syncs hardware, software, and network telemetry.
  /// Dual-redundancy: Pushes to Local Python API AND Global Firestore IT Dashboard.
  static Future<void> syncBoardTelemetry(String boardUid) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final connectivityResult = await Connectivity().checkConnectivity();
      final fingerprint = await HardwareFingerprintService.getDeviceId();

      Map<String, dynamic> hardware = {};
      String osVersion = "Unknown";

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        hardware = {
          "manufacturer": androidInfo.manufacturer,
          "model": androidInfo.model,
          "device": androidInfo.device,
          "is_physical_device": androidInfo.isPhysicalDevice,
        };
        osVersion = "Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})";
      } else if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await _deviceInfo.windowsInfo;
        hardware = {
          "computer_name": windowsInfo.computerName,
          "number_of_cores": windowsInfo.numberOfCores,
          "system_memory_in_megabytes": windowsInfo.systemMemoryInMegabytes,
        };
        osVersion = "Windows ${windowsInfo.releaseId} (Build ${windowsInfo.buildNumber})";
      }

      // Determine network type
      String network = "Offline";
      if (connectivityResult == ConnectivityResult.wifi) network = "Wi-Fi";
      if (connectivityResult == ConnectivityResult.ethernet) network = "Ethernet";

      // Build the Telemetry Payload
      final payload = {
        "board_uid": boardUid,
        "fingerprint": fingerprint,
        "hardware": hardware,
        "software": {
          "os_version": osVersion,
          "app_version": packageInfo.version,
        },
        "network": network,
        "timestamp": FieldValue.serverTimestamp(),
        "status": "ONLINE",
      };

      // 1. Push to Local Python "Brain" API (Primary)
      try {
        await http.post(
          Uri.parse(_localApiUrl),
          body: jsonEncode(payload),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));
        print('📡 [Telemetry] Local Heartbeat Sent.');
      } catch (e) {
        print('⚠️ [Telemetry] Local Heartbeat Failed: $e');
      }

      // 2. Push to Global Cloud Firestore (Secondary - IT Fleet Monitoring)
      try {
        await FirebaseFirestore.instance
            .collection('boards_telemetry')
            .doc(boardUid)
            .set(payload, SetOptions(merge: true));
        print('☁️ [Telemetry] Cloud Firestore Heartbeat Synced.');
      } catch (e) {
        print('⚠️ [Telemetry] Cloud Heartbeat Failed: $e');
      }
    } catch (e) {
      print('❌ [Telemetry] Failed to sync heartbeat: $e');
    }
  }
}
