import 'dart:async';
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

void main() => runApp(const CooldownDemoApp());

class CooldownDemoApp extends StatelessWidget {
  const CooldownDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: const CooldownDemoScreen(),
    );
  }
}

class CooldownDemoScreen extends StatefulWidget {
  const CooldownDemoScreen({super.key});

  @override
  State<CooldownDemoScreen> createState() => _CooldownDemoScreenState();
}

class _CooldownDemoScreenState extends State<CooldownDemoScreen> {
  int _secondsRemaining = 120;
  late Timer _timer;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _isRunning = true;
    _secondsRemaining = 120;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          _secondsRemaining = 0;
          _timer.cancel();
          _isRunning = false;
        }
      });
    });
  }

  void _reset() {
    _timer.cancel();
    setState(() {
      _secondsRemaining = 120;
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'COOLDOWN PROGRESS DIAL',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 60),
            _buildLockIcon(),
            const SizedBox(height: 60),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildButton(
                  label: _isRunning ? 'RESET' : 'START 120s',
                  onTap: _isRunning ? _reset : _startCooldown,
                  color: _isRunning ? AppColors.warningAmber : AppColors.primaryTeal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildLockIcon() {
    final isWiping = _secondsRemaining > 0;
    final minutes = (_secondsRemaining / 60).floor();
    final seconds = _secondsRemaining % 60;

    String label;
    if (isWiping) {
      label =
          'COOLDOWN PHASE\n${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
                  value: _secondsRemaining / 120.0,
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
                color: isWiping
                    ? AppColors.error
                    : Colors.white.withValues(alpha: 0.5),
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
            color: isWiping
                ? AppColors.error
                : Colors.white.withValues(alpha: 0.3),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
