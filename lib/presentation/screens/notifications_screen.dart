import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/board_notification.dart';
import '../../services/notification_listener_service.dart';
import '../../core/utils/logger.dart';
import 'notification_detail_screen.dart';

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

  Color _colorForPriority(NotificationPriority p) {
    switch (p) {
      case NotificationPriority.emergency:
        return const Color(0xFFC72C31);
      case NotificationPriority.high:
        return const Color(0xFFF59E0B);
      case NotificationPriority.normal:
        return AppColors.primaryTeal;
      case NotificationPriority.low:
        return AppColors.primaryTeal;
    }
  }

  String _labelForPriority(NotificationPriority p) {
    switch (p) {
      case NotificationPriority.emergency:
        return 'EMERGENCY';
      case NotificationPriority.high:
        return 'IMPORTANT';
      case NotificationPriority.normal:
        return 'BREAK';
      case NotificationPriority.low:
        return '';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForAttachment(String? type, String name) {
    if (type != null) {
      if (type.startsWith('image/')) return Icons.image_outlined;
      if (type.startsWith('application/pdf') || name.endsWith('.pdf')) {
        return Icons.picture_as_pdf;
      }
    }
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  void _openDetail(BoardNotification notification) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotificationDetailScreen(notification: notification),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final documentsEnabled = AppConfig.enableDocuments;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
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
                      style: GoogleFonts.inter(
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
                final hasDoc = documentsEnabled && notification.hasAttachment;

                return GestureDetector(
                  onTap: () => _openDetail(notification),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : Colors.white,
                        border: Border(
                          top: BorderSide(
                            color: hasDoc
                                ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.2 : 0.15)
                                : isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                          ),
                          right: BorderSide(
                            color: hasDoc
                                ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.2 : 0.15)
                                : isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                          ),
                          bottom: BorderSide(
                            color: hasDoc
                                ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.2 : 0.15)
                                : isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (notification.priority != NotificationPriority.low)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 4,
                                  color: _colorForPriority(notification.priority),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    _notificationService.deleteNotificationPermanently(notification.id);
                                  },
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.04)
                                          : Colors.black.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: isDark ? Colors.white24 : Colors.black26,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(_timeAgo(notification.timestamp),
                                    style: GoogleFonts.inter(
                                        color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 52, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
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
                                    const SizedBox(width: 16),
                                    if (notification.priority != NotificationPriority.low)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _colorForPriority(notification.priority)
                                              .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _labelForPriority(notification.priority),
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: _colorForPriority(notification.priority),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(notification.title,
                                              style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                          const SizedBox(height: 4),
                                          Text(notification.body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                  color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // Attachment indicator
                                if (hasDoc) ...[
                                  const SizedBox(height: 12),
                                  _buildAttachmentIndicator(notification),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAttachmentIndicator(BoardNotification notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.15 : 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForAttachment(notification.attachmentType, notification.displayAttachmentName),
            size: 16,
            color: AppColors.primaryTeal,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              notification.displayAttachmentName,
              style: GoogleFonts.inter(
                color: AppColors.primaryTeal,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (notification.attachmentSize != null) ...[
            const SizedBox(width: 6),
            Text(
              _formatFileSize(notification.attachmentSize),
              style: GoogleFonts.inter(color: Colors.grey, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
