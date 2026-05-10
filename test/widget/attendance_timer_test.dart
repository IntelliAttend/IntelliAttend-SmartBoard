import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/presentation/widgets/attendance_timer.dart';

void main() {
  testWidgets('AttendanceTimer counts down and triggers callback', (WidgetTester tester) async {
    bool finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceTimer(
            totalSeconds: 2,
            onTimerFinished: () => finished = true,
          ),
        ),
      ),
    );

    expect(find.text('00:02'), findsOneWidget);
    expect(finished, isFalse);

    // Advance past all timer ticks: 2 → 1 → 0 → callback
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(finished, isTrue);
  });
}
