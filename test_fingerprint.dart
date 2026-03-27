import 'dart:convert';
import 'lib/services/hardware_fingerprint_service.dart';

void main() async {
  try {
    print('\n======================================================');
    print(' STEP 1: GATHERING UNBREAKABLE TRIO FINGERPRINT');
    print('======================================================');
    
    // Note: This function will print the "Hardware Debug String" internally
    // which shows the concatenation of (SMBIOS_UUID|MachineGuid|ProcessorID)
    final fingerprint = await HardwareFingerprintService.getWindowsFingerprint();
    
    print('\n======================================================');
    print(' STEP 2: GENERATED DEVICE ID (SHA-256 HASH)');
    print('======================================================');
    print('Hash: $fingerprint');
    print('(This string acts as an un-spoofable ironclad anchor)');

    print('\n======================================================');
    print(' STEP 3: DATA PREPARED FOR THE SERVER (API CALL)');
    print('======================================================');
    
    final body = jsonEncode({
      'otp': '847291', // Faculty enters this on the SmartBoard UI
    });
    
    print('METHOD:  POST');
    print('URL:     https://api.intelliattend.edu/v1/board/session/initiate');
    print('HEADERS: {');
    print('           "Content-Type": "application/json",');
    print('           "X-Board-MAC":  "$fingerprint"');
    print('         }');
    print('BODY:    $body');
    print('======================================================\n');
    
  } catch(e) {
    print('Test Error: $e');
  }
}
