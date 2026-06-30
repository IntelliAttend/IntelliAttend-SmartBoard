import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/board_notification.dart';
import '../../services/notification_listener_service.dart';

class NotificationBell extends StatefulWidget {
  final Color iconColor;
  final VoidCallback? onViewAll;

  const NotificationBell({
    super.key,
    required this.iconColor,
    this.onViewAll,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  StreamSubscription<List<BoardNotification>>? _sub;
  List<BoardNotification> _notifications = [];

  List<BoardNotification> _filter(List<BoardNotification> list) =>
      list.where((n) =>
          n.priority == NotificationPriority.normal ||
          n.priority == NotificationPriority.low).toList();

  int get _unread => _notifications.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _notifications = _filter(NotificationListenerService().cachedNotifications);
    _sub = NotificationListenerService().notificationsStream.listen((list) {
      if (mounted) setState(() => _notifications = _filter(list));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: widget.onViewAll,
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
}
