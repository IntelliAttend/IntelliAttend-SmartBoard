import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/notification_listener_service.dart';
import '../../core/utils/logger.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationListenerService _notificationService =
      NotificationListenerService();
  List<BoardNotification> _notifications = [];
  StreamSubscription<List<BoardNotification>>? _subscription;

  @override
  void initState() {
    super.initState();
    _notifications = _notificationService.cachedNotifications;
    _subscription = _notificationService.notificationsStream.listen((list) {
      if (mounted) setState(() => _notifications = list);
    }, onError: (e) {
      Log.w('[NotificationsScreen] Stream error: $e');
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'alert':
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'attendance':
        return Icons.fact_check_outlined;
      case 'system':
        return Icons.system_update;
      case 'message':
        return Icons.message_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'alert':
      case 'warning':
        return Colors.orange;
      case 'attendance':
        return AppColors.successLime;
      case 'system':
        return AppColors.primaryTeal;
      case 'message':
        return Colors.blue;
      default:
        return AppColors.primaryTeal;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor:
            isDark ? Colors.white : AppColors.textPrimaryLight,
      ),
      body: _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 64,
                      color: isDark ? Colors.white24 : Colors.black12),
                  const SizedBox(height: 16),
                  Text('No notifications yet',
                      style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.white38 : Colors.black26)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(40),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            _colorForType(notification.type)
                                .withValues(alpha: 0.1),
                        child: Icon(
                          _iconForType(notification.type),
                          color: _colorForType(notification.type),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(notification.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(notification.body,
                                style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(_timeAgo(notification.timestamp),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
