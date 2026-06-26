import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/notification_listener_service.dart';

class PriorityOneOverlay extends StatefulWidget {
  final Widget child;
  const PriorityOneOverlay({super.key, required this.child});

  @override
  State<PriorityOneOverlay> createState() => _PriorityOneOverlayState();
}

class _PriorityOneOverlayState extends State<PriorityOneOverlay>
    with TickerProviderStateMixin {
  final NotificationListenerService _notifService = NotificationListenerService();
  StreamSubscription<List<BoardNotification>>? _sub;
  List<BoardNotification> _notifications = [];

  int _secondsRemaining = 60;
  Timer? _countdownTimer;
  bool _canDismiss = false;

  late final AnimationController _borderCtrl;

  BoardNotification? get _active =>
      _notifications.where((n) => n.priority == NotificationPriority.high).firstOrNull;

  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _notifications = _notifService.cachedNotifications;
    _sub = _notifService.notificationsStream.listen((list) {
      if (mounted) {
        setState(() {
          _notifications = list;
          _onHighPriorityChanged();
        });
      }
    });

    _borderCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _borderCtrl.repeat();

    _wasActive = _active != null;
    if (_wasActive) {
      _startCountdown();
      _setAlwaysOnTop(true);
    }
  }

  void _onHighPriorityChanged() {
    final nowActive = _active != null;
    if (nowActive && !_wasActive) {
      _wasActive = true;
      _startCountdown();
      _setAlwaysOnTop(true);
    } else if (!nowActive && _wasActive) {
      _wasActive = false;
      _resetCountdown();
      _setAlwaysOnTop(false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = 60;
    _canDismiss = false;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _canDismiss = true);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = 60;
    _canDismiss = false;
  }

  void _dismiss() {
    final n = _active;
    if (n != null) {
      _notifService.removeNotification(n.id);
    }
  }

  void _setAlwaysOnTop(bool onTop) {
    try {
      windowManager.setAlwaysOnTop(onTop);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    _borderCtrl.dispose();
    if (_wasActive) {
      _setAlwaysOnTop(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_active != null) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    final n = _active!;
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _borderCtrl,
                builder: (context, child) {
                  final angle = _borderCtrl.value * math.pi * 2;
                  return Container(
                    width: 500,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 50,
                          offset: const Offset(0, 25),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        if (child != null) child,
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _FlowBorderPainter(
                                angle: angle,
                                canDismiss: _canDismiss,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Icon(Icons.warning_amber_rounded, size: 64, color: Color(0xFFF59E0B)),
                      const SizedBox(height: 16),
                      Text(
                        n.title,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n.body,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: const Color(0xFF475569),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: 200,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _canDismiss ? _dismiss : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _canDismiss
                                ? const Color(0xFFF59E0B)
                                : Colors.grey.shade200,
                            foregroundColor: _canDismiss ? Colors.white : Colors.grey.shade500,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: _canDismiss ? 2 : 0,
                          ),
                          child: Text(
                            'Dismiss',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowBorderPainter extends CustomPainter {
  final double angle;
  final bool canDismiss;

  _FlowBorderPainter({required this.angle, required this.canDismiss});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final innerRect = Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5);
    final innerRrect = RRect.fromRectAndRadius(innerRect, const Radius.circular(21.5));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + math.pi * 2,
      colors: [
        const Color(0xFFF59E0B).withValues(alpha: 0.0),
        const Color(0xFFF59E0B).withValues(alpha: canDismiss ? 0.2 : 0.6),
        const Color(0xFFF59E0B).withValues(alpha: canDismiss ? 0.5 : 1.0),
        const Color(0xFFF59E0B).withValues(alpha: canDismiss ? 0.2 : 0.6),
        const Color(0xFFF59E0B).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
    );

    paint.shader = gradient.createShader(rect);
    canvas.drawRRect(innerRrect, paint);
  }

  @override
  bool shouldRepaint(covariant _FlowBorderPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.canDismiss != canDismiss;
}
