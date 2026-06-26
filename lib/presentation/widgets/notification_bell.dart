import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/notification_listener_service.dart';

class NotificationBell extends StatefulWidget {
  final Color iconColor;
  final bool isBreak;
  final VoidCallback? onViewAll;

  const NotificationBell({
    super.key,
    required this.iconColor,
    this.isBreak = false,
    this.onViewAll,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _lineDrop;
  late final Animation<double> _lineExpand;
  late final Animation<double> _boxExpand;
  late final Animation<double> _contentFade;

  final GlobalKey _bellKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  StreamSubscription<List<BoardNotification>>? _sub;
  List<BoardNotification> _notifications = [];
  bool _isOpen = false;

  List<BoardNotification> _filter(List<BoardNotification> list) =>
      list.where((n) =>
          n.priority == NotificationPriority.normal ||
          n.priority == NotificationPriority.low).toList();

  BoardNotification? get _latest {
    final filtered = _notifications;
    if (filtered.isEmpty) return null;
    if (widget.isBreak) {
      return filtered.firstWhere(
        (n) => n.priority == NotificationPriority.normal,
        orElse: () => filtered.first,
      );
    }
    return filtered.firstWhere(
      (n) => n.priority == NotificationPriority.low,
      orElse: () => filtered.first,
    );
  }

  int get _unread => _notifications.where((n) => !n.read).length;

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
    _lineExpand = Tween<double>(begin: 0, end: 320).animate(
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

    _notifications = _filter(NotificationListenerService().cachedNotifications);
    _sub = NotificationListenerService().notificationsStream.listen((list) {
      if (mounted) setState(() => _notifications = _filter(list));
    });
  }

  @override
  void didUpdateWidget(NotificationBell old) {
    super.didUpdateWidget(old);
    if (widget.isBreak && !old.isBreak) {
      _open();
    } else if (!widget.isBreak && old.isBreak) {
      _close();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    if (_isOpen) return;
    _isOpen = true;
    _showOverlay();
    _controller.forward(from: 0);
  }

  void _close() {
    if (!_isOpen) return;
    _isOpen = false;
    _controller.reverse().then((_) => _removeOverlay());
  }

  void _toggle() => _isOpen ? _close() : _open();

  void _showOverlay() {
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final offset = box.localToGlobal(Offset.zero);
    final top = offset.dy + box.size.height;
    final left = offset.dx + box.size.width / 2 - 160;

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: top,
            left: left,
            child: Material(color: Colors.transparent, child: _buildDropdown()),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ─── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _bellKey,
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _toggle,
          icon: Icon(Icons.notifications_none, color: widget.iconColor),
        ),
        if (_unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration:
                  const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
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
        // Stage 2: horizontal teal bar (width 0 → 320)
        AnimatedBuilder(
          animation: _lineExpand,
          builder: (_, __) => Container(
            width: _lineExpand.value,
            height: 2,
            color: AppColors.primaryTeal,
          ),
        ),
        // Stage 3-4: notification box + content
        AnimatedBuilder(
          animation: _boxExpand,
          builder: (_, __) {
            return ClipRect(
              clipper: _HeightClipper(_boxExpand.value, 80),
              child: GestureDetector(
                onTap: () {
                  _close();
                  widget.onViewAll?.call();
                },
                child: Container(
                  width: 320,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: AppColors.primaryTeal, width: 2),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Opacity(
                    opacity: _contentFade.value,
                    child: _latest != null
                        ? _buildContent(_latest!)
                        : _buildEmpty(),
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
              color: AppColors.primaryTeal.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(n.type),
              color: AppColors.primaryTeal,
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
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  n.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'No new notifications',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.message_outlined;
      case 'attendance':
        return Icons.assignment_turned_in_outlined;
      case 'system':
        return Icons.info_outline;
      default:
        return Icons.notifications_outlined;
    }
  }
}

class _HeightClipper extends CustomClipper<Rect> {
  final double current;
  final double max;
  _HeightClipper(this.current, this.max);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, current);

  @override
  bool shouldReclip(_HeightClipper old) => old.current != current;
}
