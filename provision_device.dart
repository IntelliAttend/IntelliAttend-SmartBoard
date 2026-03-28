import 'dart:io';
import 'lib/services/api_service.dart';
import 'lib/services/hardware_fingerprint_service.dart';

void main() async {
  print('--- IntelliAttend Device Provisioner (Phase 1) ---');
  
  try {
    // 1. Fetch hardware signature
    print('[Provisioner] Gathering hardware fingerprint...');
    final fingerprint = await HardwareFingerprintService.getWindowsFingerprint();
    print('[Provisioner] Silicon Signature: $fingerprint');

    // 2. Define the room mapping (This would normally be input by the IT Admin)
    const roomId = 'ROOM_CSE_402';
    const roomName = 'CSE Seminar Hall 402';
    const building = 'Block B';
    const department = 'Computer Science & Engineering';

    print('[Provisioner] Registering device to $roomName ($roomId)...');

    // 3. Perform registration via ApiService
    // Note: This requires the FastAPI server to be running on localhost:8000
    final result = await ApiService.registerDevice(
      roomId: roomId,
      roomName: roomName,
      building: building,
      department: department,
      rosterCount: 55,
    );

    if (result['status'] == 'success') {
      print('\n======================================================');
      print(' SUCCESS: SmartBoard Bound Successfully!');
      print(' Message: ${result['message']}');
      print('======================================================\n');
      print('You can now use this SmartBoard for daily attendance.');
    } else {
      print('[Error] Registration failed: ${result['message']}');
    }

  } catch (e) {
    print('\n[CRITICAL ERROR] Provisioning failed: $e');
    print('Ensure the Backend (FastAPI) is running at http://127.0.0.1:8000');
  }
}
