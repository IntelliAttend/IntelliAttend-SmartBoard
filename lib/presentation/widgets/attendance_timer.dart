import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
        if (mounted) setState(() => _remaining--);
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$minutes:$seconds',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: _remaining < 30 ? AppColors.error : AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'REMAINING ATTENDANCE WINDOW',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
