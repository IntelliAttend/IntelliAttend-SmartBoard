import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'hardware_fingerprint_service.dart';
import '../core/utils/logger.dart';

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
        osVersion =
            "Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})";
      } else if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await _deviceInfo.windowsInfo;
        hardware = {
          "computer_name": windowsInfo.computerName,
          "number_of_cores": windowsInfo.numberOfCores,
          "system_memory_in_megabytes": windowsInfo.systemMemoryInMegabytes,
        };
        osVersion =
            "Windows ${windowsInfo.releaseId} (Build ${windowsInfo.buildNumber})";
      }

      // Determine network type
      String network = "Offline";
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        network = "Wi-Fi";
      }
      if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        network = "Ethernet";
      }

      final timestampMs = DateTime.now().millisecondsSinceEpoch;

      // Build a JSON-safe payload for the local Python API.
      final localPayload = {
        "board_uid": boardUid,
        "fingerprint": fingerprint,
        "hardware": hardware,
        "software": {
          "os_version": osVersion,
          "app_version": packageInfo.version,
        },
        "network": network,
        "timestamp_ms": timestampMs,
        "status": "ONLINE",
      };

      final cloudPayload = {
        ...localPayload,
        "timestamp": FieldValue.serverTimestamp(),
      };

      // 1. Push to Local Python "Brain" API (Primary)
      try {
        await http.post(
          Uri.parse(_localApiUrl),
          body: jsonEncode(localPayload),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));
        Log.i('📡 [Telemetry] Local Heartbeat Sent.');
      } catch (e) {
        Log.w('⚠️ [Telemetry] Local Heartbeat Failed: $e');
      }

      // 2. Push to Global Cloud Firestore (Secondary - IT Fleet Monitoring)
      try {
        await FirebaseFirestore.instance
            .collection('boards_telemetry')
            .doc(boardUid)
            .set(cloudPayload, SetOptions(merge: true));
        Log.i('☁️ [Telemetry] Cloud Firestore Heartbeat Synced.');
      } catch (e) {
        Log.w('⚠️ [Telemetry] Cloud Heartbeat Failed: $e');
      }
    } catch (e) {
      Log.w('❌ [Telemetry] Failed to sync heartbeat: $e');
    }
  }
}
