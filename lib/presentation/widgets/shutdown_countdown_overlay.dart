import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/platform/power_command_service.dart';

class ShutdownCountdownOverlay extends StatefulWidget {
  final Widget child;
  const ShutdownCountdownOverlay({super.key, required this.child});

  @override
  State<ShutdownCountdownOverlay> createState() =>
      _ShutdownCountdownOverlayState();
}

class _ShutdownCountdownOverlayState extends State<ShutdownCountdownOverlay>
    with SingleTickerProviderStateMixin {
  final PowerCommandService _powerCmd = PowerCommandService();
  PowerCommandState _state = const PowerCommandState();
  StreamSubscription<PowerCommandState>? _sub;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _state = _powerCmd.currentState;
    _sub = _powerCmd.onStateChanged.listen((s) {
      if (mounted) {
        setState(() {
          _state = s;
        });
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_state.status == PowerCommandStatus.pendingShutdown)
          _buildOverlay(),
      ],
    );
  }

  Color get _ringColor =>
      _state.secondsRemaining <= 10 ? AppColors.error : AppColors.warningAmber;

  Color get _ringColorBg =>
      _state.secondsRemaining <= 10
          ? AppColors.error.withValues(alpha: 0.1)
          : AppColors.warningAmber.withValues(alpha: 0.1);

  Widget _buildOverlay() {
    final fraction = _state.totalSeconds > 0
        ? _state.secondsRemaining / _state.totalSeconds
        : 1.0;

    final isUrgent = _state.secondsRemaining <= 10;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // ← Blur background
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: AppColors.bgDark.withValues(alpha: 0.8),
                ),
              ),
            ),
            // ← Grid pattern overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.025,
                  child: CustomPaint(
                    painter: _GridPainter(),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Shutdown status label ──
                    Text(
                      'SHUTDOWN INITIATED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isUrgent ? AppColors.error : AppColors.warningAmber,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Title ──
                    Text(
                      'System Shutdown',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Reason ──
                    if (_state.reason != null && _state.reason!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 80),
                        child: Text(
                          _state.reason!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    const SizedBox(height: 48),

                    // ── Hanging Lock style countdown ring ──
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) {
                        final glowOpacity = isUrgent ? 0.12 * _pulseAnim.value : 0.0;
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: glowOpacity > 0
                                ? [
                                    BoxShadow(
                                      color: AppColors.error.withValues(alpha: glowOpacity),
                                      blurRadius: 50 * _pulseAnim.value,
                                      spreadRadius: 6 * _pulseAnim.value,
                                    ),
                                  ]
                                : null,
                          ),
                          child: child,
                        );
                      },
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Progress ring
                            SizedBox(
                              width: 200,
                              height: 200,
                              child: CircularProgressIndicator(
                                value: fraction,
                                strokeWidth: 3,
                                backgroundColor: _ringColorBg,
                                valueColor: AlwaysStoppedAnimation<Color>(_ringColor),
                              ),
                            ),
                            // Icon inside circular container with pulse
                            AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (_, child) => Transform.scale(
                                scale: _pulseAnim.value,
                                child: child,
                              ),
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isUrgent
                                      ? AppColors.error.withValues(alpha: 0.15)
                                      : AppColors.warningAmber.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: isUrgent
                                        ? AppColors.error.withValues(alpha: 0.3)
                                        : AppColors.warningAmber.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.power_settings_new_rounded,
                                  size: 48,
                                  color: isUrgent
                                      ? AppColors.error
                                      : AppColors.warningAmber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Big countdown digits ──
                    Text(
                      '${_state.secondsRemaining}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SECONDS REMAINING',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 56),

                    // ── Cancel shutdown ──
                    _buildCancelButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: 300,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => _powerCmd.cancelFromLocal(),
        icon: const Icon(Icons.close, size: 22),
        label: const Text(
          'Cancel Shutdown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Subtle grid pattern for the overlay background.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;

    const spacing = 60.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
