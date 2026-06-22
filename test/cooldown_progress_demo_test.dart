import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intelliattend_smartboard/core/theme/app_theme.dart';

/// Standalone widget that replicates the exact cooldown lock icon UI
/// from [IdleScreen._buildHangingLock] with a controllable countdown,
/// so we can visually verify the 120-second progress dial in tests.
class CooldownLockIcon extends StatelessWidget {
  final int cooldownSecondsRemaining;
  final String labelOverride;

  const CooldownLockIcon({
    super.key,
    required this.cooldownSecondsRemaining,
    this.labelOverride = '',
  });

  @override
  Widget build(BuildContext context) {
    final isWiping = cooldownSecondsRemaining > 0;

    String label;
    if (isWiping) {
      if (labelOverride.isNotEmpty) {
        label = labelOverride;
      } else {
        final minutes = (cooldownSecondsRemaining / 60).floor();
        final seconds = cooldownSecondsRemaining % 60;
        label =
            'COOLDOWN PHASE\n${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }
    } else {
      label = 'SESSION LOCKED';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 40,
          color: Colors.white.withValues(alpha: 0.2),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            if (isWiping)
              SizedBox(
                width: 66,
                height: 66,
                child: CircularProgressIndicator(
                  value: cooldownSecondsRemaining / 120.0,
                  strokeWidth: 3,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.error),
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isWiping
                    ? AppColors.error.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isWiping
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                Icons.lock_outline,
                color: isWiping ? AppColors.error : Colors.white.withValues(alpha: 0.5),
                size: 32,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isWiping ? AppColors.error : Colors.white.withValues(alpha: 0.3),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

/// Helper: returns the full label string for a given countdown value.
String cooldownLabel(int seconds) {
  final m = (seconds / 60).floor();
  final s = seconds % 60;
  return 'COOLDOWN PHASE\n${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

void main() {
  group('Cooldown Progress Dial – Visual Demo', () {
    /// Pumps a centered [CooldownLockIcon] in a dark-themed MaterialApp.
    Future<void> pumpIcon(
      WidgetTester tester, {
      required int secondsRemaining,
      String labelOverride = '',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            backgroundColor: AppColors.bgDark,
            body: Center(
              child: CooldownLockIcon(
                cooldownSecondsRemaining: secondsRemaining,
                labelOverride: labelOverride,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('1) 120s remaining – full ring, label shows COOLDOWN PHASE 02:00',
        (WidgetTester tester) async {
      await pumpIcon(tester, secondsRemaining: 120);

      // Label is a single Text widget "COOLDOWN PHASE\n02:00"
      expect(find.text(cooldownLabel(120)), findsOneWidget);

      // Circular progress indicator exists with value == 1.0 (full)
      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, closeTo(1.0, 0.001));
      expect(progress.valueColor!.value, AppColors.error);
      expect(progress.backgroundColor, AppColors.error.withValues(alpha: 0.1));

      // Lock icon
      final icon = tester.widget<Icon>(find.byIcon(Icons.lock_outline));
      expect(icon.color, AppColors.error);

      // Label text style
      final labelText = tester.widget<Text>(find.text(cooldownLabel(120)));
      expect(labelText.style!.color, AppColors.error);
    });

    testWidgets('2) 60s remaining – half ring, label shows COOLDOWN PHASE 01:00',
        (WidgetTester tester) async {
      await pumpIcon(tester, secondsRemaining: 60);

      expect(find.text(cooldownLabel(60)), findsOneWidget);

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, closeTo(0.5, 0.001));
    });

    testWidgets('3) 10s remaining – nearly empty ring, label shows COOLDOWN PHASE 00:10',
        (WidgetTester tester) async {
      await pumpIcon(tester, secondsRemaining: 10);

      expect(find.text(cooldownLabel(10)), findsOneWidget);

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, closeTo(10 / 120, 0.001));
    });

    testWidgets('4) 1s remaining – nearly empty ring, label shows COOLDOWN PHASE 00:01',
        (WidgetTester tester) async {
      await pumpIcon(tester, secondsRemaining: 1);

      expect(find.text(cooldownLabel(1)), findsOneWidget);

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, closeTo(1 / 120, 0.001));
    });

    testWidgets('5) 0s remaining – no ring, label shows SESSION LOCKED',
        (WidgetTester tester) async {
      await pumpIcon(tester, secondsRemaining: 0);

      expect(find.text('SESSION LOCKED'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('6) Animated countdown: 120s → 0s simulates full cooldown',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            backgroundColor: AppColors.bgDark,
            body: const Center(
              child: _AnimatedCooldownDemo(),
            ),
          ),
        ),
      );

      // Initial: 120s remaining → full ring
      expect(find.text(cooldownLabel(120)), findsOneWidget);
      expect(
        tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        ).value,
        closeTo(1.0, 0.001),
      );

      // Tick 60 seconds
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      // At 60s: half ring
      expect(find.text(cooldownLabel(60)), findsOneWidget);
      expect(
        tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        ).value,
        closeTo(0.5, 0.01),
      );

      // Tick remaining 60 seconds
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      // At 0s: ring gone, label reset
      expect(find.text('SESSION LOCKED'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

/// Internal stateful widget that ticks a 120-second countdown in real time,
/// demonstrating the full cooldown animation cycle during widget tests.
class _AnimatedCooldownDemo extends StatefulWidget {
  const _AnimatedCooldownDemo();

  @override
  State<_AnimatedCooldownDemo> createState() => _AnimatedCooldownDemoState();
}

class _AnimatedCooldownDemoState extends State<_AnimatedCooldownDemo> {
  int _remaining = 120;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _remaining--;
      });
      if (_remaining > 0) {
        _startTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CooldownLockIcon(cooldownSecondsRemaining: _remaining);
  }
}
