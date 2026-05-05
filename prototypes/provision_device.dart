import 'dart:io';
import 'lib/services/device_service.dart';
import 'lib/services/session_manager.dart';

void main() async {
  // Ensure the app environment is initialized
  await SessionManager.init();

  const String roomId = 'room_402';
  const String roomName = 'Computer Networks Lab';
  const int capacity = 60;

  print('📘 [v5.3 Titan] Provisioning SmartBoard Hardware...');
  print('Target Room: $roomId ($roomName)');

  try {
    // 3. Perform registration via DeviceService (v5.3 Titan)
    // This handles the cloud staging handshake and local vault storage.
    await DeviceService.register(
      roomId: roomId,
      deviceName: roomName,
      rosterCount: capacity,
    );

    print('\n======================================================');
    print('✅ PROVISIONING COMPLETE');
    print('Hardware Fingerprint is now bound to $roomId');
    print('Layer 1 Bedrock initialized for offline operation.');
    print('======================================================\n');
  } catch (e) {
    print('\n❌ PROVISIONING FAILED');
    print('Error: $e');
    print('Ensure the backend is reachable at https://dev-api.balaseetharamanjaneyulu.com\n');
    exit(1);
  }

  exit(0);
}
