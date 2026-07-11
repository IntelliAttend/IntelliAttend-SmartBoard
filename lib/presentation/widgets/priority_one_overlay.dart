import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../models/board_notification.dart';
import '../../services/notification_listener_service.dart';

class PriorityOneOverlay extends StatefulWidget {
  final Widget child;
  const PriorityOneOverlay({super.key, required this.child});

  @override
  State<PriorityOneOverlay> createState() => _PriorityOneOverlayState();
}

class _PriorityOneOverlayState extends State<PriorityOneOverlay>
    with SingleTickerProviderStateMixin {
  final NotificationListenerService _notifService = NotificationListenerService();
  StreamSubscription<List<BoardNotification>>? _sub;
  List<BoardNotification> _notifications = [];

  int _secondsRemaining = 60;
  int _totalDuration = 60;
  Timer? _countdownTimer;
  bool _canDismiss = false;

  late final AnimationController _smoothCtrl;
  double _displayProgress = 0.0;
  double _prevProgress = 0.0;
  double _targetProgress = 0.0;

  BoardNotification? get _active =>
      _notifications.where((n) =>
          n.priority == NotificationPriority.high ||
          n.priority == NotificationPriority.normal).firstOrNull;

  bool get _isP1 => _active?.priority == NotificationPriority.high;
  bool get _isP2 => _active?.priority == NotificationPriority.normal;

  bool _wasActive = false;
  String? _lastShownNotificationId;
  bool _startupSnapshotCaptured = false;
  final Set<String> _startupNotificationIds = {};

  @override
  void initState() {
    super.initState();
    // Never populate from vault cache at mount — only live WebSocket
    // notifications should show overlays.
    _notifications = [];
    _sub = _notifService.notificationsStream.listen((list) {
      if (mounted) {
        if (_notifService.isStartingUp) return;
        // Capture snapshot of ALL existing notifications on first
        // post-startup stream event. This includes vault-loaded items
        // that weren't present at mount time. Only notifications
        // arriving AFTER this snapshot should trigger overlays.
        if (!_startupSnapshotCaptured) {
          _startupNotificationIds.addAll(list.map((n) => n.id));
          _startupSnapshotCaptured = true;
        }
        setState(() {
          _notifications = list;
          _onHighPriorityChanged();
        });
      }
    });

    _smoothCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _smoothCtrl.addListener(_onSmoothUpdate);

    _wasActive = _active != null;
    // Do NOT auto-activate overlays from persisted vault state on startup.
    // Only live notifications (via WebSocket) should trigger overlays.
  }

  void _onHighPriorityChanged() {
    if (_notifService.isStartingUp) return;
    final nowActive = _active;

    // If we're currently showing an overlay, check if our notification
    // is still the active one. If not (dismissed or replaced), deactivate.
    if (_wasActive) {
      final currentNid = nowActive?.notificationId ?? nowActive?.id;
      if (currentNid != _lastShownNotificationId) {
        _wasActive = false;
        _lastShownNotificationId = null;
        _resetCountdown();
        _releaseWindowFromFront();
      }
      return;
    }

    // Not currently active — check if we should activate.
    if (nowActive != null) {
      if (_startupNotificationIds.contains(nowActive.id)) return;
      final nid = nowActive.notificationId ?? nowActive.id;
      _wasActive = true;
      _lastShownNotificationId = nid;
      _startCountdown();
      _forceWindowToFront();
    }
  }

  int _resolveDuration(BoardNotification n) {
    if (n.durationSeconds != null && n.durationSeconds! >= 10) {
      return n.durationSeconds!;
    }
    return 60;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_isP2) {
      setState(() {
        _canDismiss = true;
        _secondsRemaining = 0;
        _totalDuration = 0;
      });
      return;
    }
    final n = _active;
    _totalDuration = n != null ? _resolveDuration(n) : 60;
    _secondsRemaining = _totalDuration;
    _canDismiss = false;
    _displayProgress = 1.0;
    _prevProgress = 1.0;
    _targetProgress = 1.0;
    _smoothCtrl.value = 0.0;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          timer.cancel();
          _prevProgress = _targetProgress;
          _targetProgress = 0.0;
          _smoothCtrl.forward(from: 0.0).then((_) {
            if (mounted) setState(() => _canDismiss = true);
          });
        } else {
          _prevProgress = _targetProgress;
          _targetProgress = _secondsRemaining / _totalDuration;
          _smoothCtrl.forward(from: 0.0);
        }
      });
    });
  }

  void _onSmoothUpdate() {
    _displayProgress = lerpDouble(_prevProgress, _targetProgress, _smoothCtrl.value) ?? _targetProgress;
    if (mounted) setState(() {});
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = 0;
    _canDismiss = false;
  }

  Future<void> _dismiss() async {
    final n = _active;
    if (n != null) {
      if (n.notificationId != null && n.notificationId!.isNotEmpty) {
        await _notifService.dismissNotification(n.notificationId!);
      } else {
        _notifService.removeNotification(n.id);
      }
    }
  }

  static const _kioskChannel = MethodChannel('com.intelliattend/kiosk');

  Future<void> _forceWindowToFront() async {
    try {
      await _kioskChannel.invokeMethod('forceWindowToFront');
    } catch (_) {
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }

  Future<void> _releaseWindowFromFront() async {
    try {
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    _smoothCtrl.dispose();
    if (_wasActive) {
      _releaseWindowFromFront();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_active != null && _wasActive) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    final n = _active!;
    final accentColor = _isP1 ? AppColors.warningAmber : AppColors.primaryTeal;
    final timerProgress = _displayProgress;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Blur backdrop
            Positioned.fill(
              child: GestureDetector(
                onTap: _canDismiss ? null : () {},
                onPanDown: _canDismiss ? null : (_) {},
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    color: Colors.black.withValues(alpha: _isP1 ? 0.28 : 0.22),
                  ),
                ),
              ),
            ),
            // Card
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 480,
                  maxWidth: 800,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.04),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Progress border as timer (P1 only)
                      if (_isP1)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _FlowBorderPainter(
                                progress: timerProgress,
                                canDismiss: _canDismiss,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                      // Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Icon
                            Icon(
                              _isP1 ? Icons.warning_amber_rounded : Icons.info_outline,
                              size: 36,
                              color: accentColor,
                            ),
                            const SizedBox(height: 24),
                            // Title
                            Text(
                              n.title.isNotEmpty ? n.title : (_isP1 ? 'Alert' : 'Notice'),
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimaryLight,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            // Body
                            if (n.body.isNotEmpty)
                              Text(
                                n.body,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  color: Colors.grey,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            // Countdown text (P1 only, hide when expired)
                            if (_isP1 && _secondsRemaining > 0) ...[
                              const SizedBox(height: 28),
                              Text(
                                '${_secondsRemaining}s',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimaryLight.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            // Action button
                            _buildActionButton(accentColor),
                          ],
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

  Widget _buildActionButton(Color accentColor) {
    final canAct = _canDismiss;

    return SizedBox(
      height: 46,
      child: TextButton(
        onPressed: canAct ? _dismiss : null,
        style: TextButton.styleFrom(
          backgroundColor: canAct
              ? accentColor.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.04),
          foregroundColor: canAct ? accentColor : Colors.black.withValues(alpha: 0.2),
          disabledBackgroundColor: Colors.black.withValues(alpha: 0.04),
          disabledForegroundColor: Colors.black.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: canAct
                  ? accentColor.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
        ),
        child: Text(
          'DISMISS',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _FlowBorderPainter extends CustomPainter {
  final double progress;
  final bool canDismiss;
  final Color color;

  _FlowBorderPainter({
    required this.progress,
    required this.canDismiss,
    required this.color,
  });

  static const double _cornerRadius = 22.5;
  static const double _inset = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (canDismiss) return;

    final innerRect = Rect.fromLTWH(
        _inset, _inset, size.width - _inset * 2, size.height - _inset * 2);
    final rrect =
        RRect.fromRectAndRadius(innerRect, const Radius.circular(_cornerRadius));

    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final totalLength = metric.length;

    // Background track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = color.withValues(alpha: 0.1);
    canvas.drawPath(path, trackPaint);

    // Progress arc — starts from top-centre, goes clockwise
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped > 0.005) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..color = color;

      // Distance from path start (top-left) to top-centre
      final cornerArc = (math.pi / 2) * _cornerRadius;
      final topEdge = innerRect.width - 2 * _cornerRadius;
      final topCentreOffset = cornerArc + topEdge / 2;

      final drawLength = totalLength * clamped;
      final startOffset = topCentreOffset;
      final endOffset = startOffset + drawLength;

      if (endOffset <= totalLength) {
        canvas.drawPath(
            metric.extractPath(startOffset, endOffset), progressPaint);
      } else {
        // Wrap around: draw from startOffset to end, then from 0 to remainder
        canvas.drawPath(
            metric.extractPath(startOffset, totalLength), progressPaint);
        canvas.drawPath(
            metric.extractPath(0, endOffset - totalLength), progressPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowBorderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.canDismiss != canDismiss ||
      oldDelegate.color != color;
}
