
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AttendanceTimer extends StatefulWidget {
  final int totalSeconds;
  final VoidCallback onTimerFinished;

  const AttendanceTimer({super.key, required this.totalSeconds, required this.onTimerFinished});

  @override
  State<AttendanceTimer> createState() => _AttendanceTimerState();
}

class _AttendanceTimerState extends State<AttendanceTimer> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.totalSeconds;
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining > 0) {
        setState(() => _remaining--);
      } else {
        _timer?.cancel();
        widget.onTimerFinished();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remaining % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        Text(
          '$minutes:$seconds',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: _remaining < 30 ? AppColors.error : AppColors.primary,
            fontFamily: 'JetBrains Mono', // High-legibility monospaced for digits
          ),
        ),
        const SizedBox(height: 8),
        const Text('REMAINING ATTENDANCE WINDOW', style: TextStyle(letterSpacing: 4, fontSize: 10)),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
