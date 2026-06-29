import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/notification_listener_service.dart';

class NotificationPopdown extends StatefulWidget {
  final BoardNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final Duration displayDuration;

  const NotificationPopdown({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.displayDuration = const Duration(seconds: 5),
  });

  @override
  State<NotificationPopdown> createState() => _NotificationPopdownState();
}

class _NotificationPopdownState extends State<NotificationPopdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _lineDrop;
  late final Animation<double> _lineExpand;
  late final Animation<double> _boxExpand;
  late final Animation<double> _contentFade;

  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _lineDrop = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.21, curve: Curves.easeOut),
      ),
    );
    _lineExpand = Tween<double>(begin: 0, end: 340).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.21, 0.5, curve: Curves.easeOut),
      ),
    );
    _boxExpand = Tween<double>(begin: 0, end: 80).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 0.79, curve: Curves.easeOutCubic),
      ),
    );
    _contentFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.79, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
    _dismissTimer = Timer(widget.displayDuration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: GestureDetector(
        onTap: () {
          _dismissTimer?.cancel();
          _dismiss();
          widget.onTap?.call();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Stage 1: vertical teal line (height 0 → 24)
            AnimatedBuilder(
              animation: _lineDrop,
              builder: (_, __) => Container(
                width: 2,
                height: _lineDrop.value,
                color: AppColors.primaryTeal,
              ),
            ),
            // Stage 2: horizontal teal bar (width 0 → 340)
            AnimatedBuilder(
              animation: _lineExpand,
              builder: (_, __) => Container(
                width: _lineExpand.value,
                height: 2,
                color: AppColors.primaryTeal,
              ),
            ),
            // Stage 3-4: notification box with glassmorphism
            AnimatedBuilder(
              animation: _boxExpand,
              builder: (_, __) {
                return ClipRect(
                  clipper: _PopdownHeightClipper(_boxExpand.value, 80),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        width: 340,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          border: Border.all(
                            color: AppColors.primaryTeal.withValues(alpha: 0.25),
                            width: 1,
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Opacity(
                          opacity: _contentFade.value,
                          child: _buildContent(widget.notification),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BoardNotification n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _iconBgColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(n.type),
              color: _iconBgColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  n.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  n.body,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight.withValues(alpha: 0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryLight.withValues(alpha: 0.3),
            size: 20,
          ),
        ],
      ),
    );
  }

  Color get _iconBgColor {
    switch (widget.notification.priority) {
      case NotificationPriority.emergency:
        return AppColors.error;
      case NotificationPriority.high:
        return AppColors.warningAmber;
      case NotificationPriority.normal:
        return AppColors.primaryTeal;
      case NotificationPriority.low:
        return AppColors.primaryTeal;
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.message_outlined;
      case 'attendance':
        return Icons.assignment_turned_in_outlined;
      case 'system':
        return Icons.info_outline;
      case 'alert':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }
}

class _PopdownHeightClipper extends CustomClipper<Rect> {
  final double current;
  final double max;
  _PopdownHeightClipper(this.current, this.max);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, current);

  @override
  bool shouldReclip(_PopdownHeightClipper old) => old.current != current;
}
