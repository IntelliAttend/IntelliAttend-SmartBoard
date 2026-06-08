import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/platform/hardware_fingerprint_service.dart';

void main() {
  test('Brightness cycle: save current → max 100% → wait 10s → restore original', () async {
    // 1. Read the original brightness from the monitor
    final original = await HardwareFingerprintService.getCurrentBrightness();
    print('📊 Original brightness: $original');
    expect(original, isNotNull);

    // 2. Maximize brightness (saves original, sets display to 100%)
    await HardwareFingerprintService.maximizeBrightness();
    print('💡 Brightness set to 100% — look at your monitor');

    // 3. Confirm the display is now at 100%
    final during = await HardwareFingerprintService.getCurrentBrightness();
    print('📊 Current brightness (should be 100): $during');
    expect(during, equals(100));

    // 4. Hold at peak brightness for 10 seconds so you can see it
    print('⏳ Holding at 100% brightness for 10 seconds...');
    await Future.delayed(const Duration(seconds: 10));

    // 5. Restore the original brightness
    await HardwareFingerprintService.restoreBrightness();
    print('💡 Brightness restored to $original');

    // 6. Verify the monitor returned to the saved level
    final restored = await HardwareFingerprintService.getCurrentBrightness();
    print('📊 Restored brightness: $restored');
    expect(restored, equals(original));
  });
}
