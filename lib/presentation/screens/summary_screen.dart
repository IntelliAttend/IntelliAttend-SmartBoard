import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/utils/logger.dart';
import '../../main.dart';
import '../../services/session_manager.dart';
import 'idle_screen.dart';
import 'registration_screen.dart';

class SummaryScreen extends StatefulWidget {
  final String sessionId;
  final int presentCount;
  final int totalCapacity;
  final String courseName;
  final String facultyName;
  final String? slotId;

  const SummaryScreen({
    super.key,
    required this.sessionId,
    required this.presentCount,
    required this.totalCapacity,
    required this.courseName,
    required this.facultyName,
    this.slotId,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  int _secondsRemaining = 30;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    KioskService.setMode(KioskMode.fullscreen);
    _persistCompletedSession();
    _startCountdown();
  }

  Future<void> _persistCompletedSession() async {
    if (widget.slotId != null && widget.slotId!.isNotEmpty) {
      await SessionManager.recordCompletedSession(
        slotId: widget.slotId!,
        sessionId: widget.sessionId,
        courseName: widget.courseName,
        facultyName: widget.facultyName,
        attendeeCount: widget.presentCount,
      );
    }
    await SessionManager.clearSession(widget.sessionId);
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        _returnToIdle();
      }
    });
  }

  Future<void> _returnToIdle() async {
    final registration = await globalDeviceRepository.getRegistration();
    if (!mounted) return;
    if (registration != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => IdleScreen(
            registration: registration,
            completedSession: true,
          ),
        ),
      );
    } else {
      Log.w('[Summary] No registration found — navigating to registration screen.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RegistrationScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attendanceRate = widget.totalCapacity > 0
        ? (widget.presentCount / widget.totalCapacity * 100).toInt()
        : 0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              attendanceRate >= 80 ? Icons.check_circle : Icons.info_outline,
              size: 80,
              color: attendanceRate >= 80
                  ? AppColors.successLime
                  : AppColors.warningAmber,
            ),
            const SizedBox(height: 24),
            Text(
              'SESSION COMPLETE',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.courseName.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.facultyName,
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStat('PRESENT', widget.presentCount, AppColors.successLime, isDark),
                const SizedBox(width: 48),
                _buildStat('CAPACITY', widget.totalCapacity, isDark ? Colors.white38 : Colors.black38, isDark),
                const SizedBox(width: 48),
                _buildStat('RATE', '$attendanceRate%', AppColors.primaryTeal, isDark),
              ],
            ),
            const SizedBox(height: 64),
            Text(
              'Returning to idle in $_secondsRemaining s',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: _secondsRemaining / 30,
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                color: AppColors.primaryTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, dynamic value, Color color, bool isDark) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}
