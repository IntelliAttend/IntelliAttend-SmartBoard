
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/presentation/widgets/attendance_timer.dart';

void main() {
  testWidgets('AttendanceTimer counts down and triggers callback', (WidgetTester tester) async {
    bool finished = false;

    // Build the timer with 2 seconds
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

    // Initial state
    expect(find.text('00:02'), findsOneWidget);
    expect(finished, isFalse);

    // Wait 1 second
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100)); // Ensure timer task processes
    expect(find.text('00:01'), findsOneWidget);

    // Wait another second
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('00:00'), findsOneWidget);
    
    // Callback should have triggered
    expect(finished, isTrue);
  });
}
