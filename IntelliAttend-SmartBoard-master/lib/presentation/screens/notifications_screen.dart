import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/document_service.dart';
import '../../services/notification_listener_service.dart';
import '../../core/utils/logger.dart';
import 'document_viewer_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationListenerService _notificationService =
      NotificationListenerService();
  final DocumentService _documentService = DocumentService();
  List<BoardNotification> _notifications = [];
  StreamSubscription<List<BoardNotification>>? _subscription;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  final Set<String> _errorIds = {};

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

  bool _isPdf(String name) =>
      name.split('.').last.toLowerCase() == 'pdf';

  Future<void> _openAttachment(BoardNotification notification) async {
    if (!mounted) return;
    final id = notification.id;

    setState(() {
      _downloadingIds.add(id);
      _downloadProgress[id] = 0.0;
      _errorIds.remove(id);
    });

    final path = await _documentService.downloadDocument(
      notification.attachmentUrl!,
      notification.displayAttachmentName,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress[id] = progress);
        }
      },
    );

    if (!mounted) return;

    if (path == null) {
      setState(() {
        _downloadingIds.remove(id);
        _downloadProgress.remove(id);
        _errorIds.add(id);
      });
      return;
    }

    setState(() {
      _downloadingIds.remove(id);
      _downloadProgress.remove(id);
    });

    final fileName = notification.displayAttachmentName;

    if (_isPdf(fileName)) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DocumentViewerScreen(
            filePath: path,
            fileName: fileName,
          ),
        ),
      );
    } else {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No app found to open $fileName',
                style: GoogleFonts.inter(fontSize: 14)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
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
                final isDownloading = _downloadingIds.contains(notification.id);
                final hasError = _errorIds.contains(notification.id);
                final progress = _downloadProgress[notification.id] ?? 0.0;

                return GestureDetector(
                  onTap: hasDoc && !isDownloading
                      ? () => _openAttachment(notification)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasDoc
                            ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.2 : 0.15)
                            : isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
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
                            const SizedBox(width: 20),
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
                                      style: GoogleFonts.inter(
                                          color: Colors.grey)),
                                ],
                              ),
                            ),
                            Text(_timeAgo(notification.timestamp),
                                style: GoogleFonts.inter(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),

                        // Attachment section
                        if (hasDoc) ...[
                          const SizedBox(height: 16),
                          _buildAttachmentSection(
                            notification,
                            isDownloading,
                            hasError,
                            progress,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAttachmentSection(
    BoardNotification notification,
    bool isDownloading,
    bool hasError,
    double progress,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: isDownloading
          ? null
          : () => _openAttachment(notification),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.15 : 0.1),
          ),
        ),
        child: isDownloading
            ? _buildDownloadProgress(progress, isDark)
            : hasError
                ? _buildRetrySection(notification, isDark)
                : _buildAttachmentInfo(notification, isDark),
      ),
    );
  }

  Widget _buildAttachmentInfo(BoardNotification notification, bool isDark) {
    final isCached = _documentService.isCached(notification.attachmentUrl!);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _iconForAttachment(notification.attachmentType, notification.displayAttachmentName),
            color: AppColors.primaryTeal,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.displayAttachmentName,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (notification.attachmentSize != null) ...[
                const SizedBox(height: 2),
                Text(
                  _formatFileSize(notification.attachmentSize),
                  style: GoogleFonts.inter(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isCached)
          Icon(
            Icons.check_circle,
            color: AppColors.successLime,
            size: 20,
          )
        else
          Icon(
            Icons.download_rounded,
            color: AppColors.primaryTeal,
            size: 20,
          ),
      ],
    );
  }

  Widget _buildDownloadProgress(double progress, bool isDark) {
    final percent = (progress * 100).toInt();

    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
              Text(
                '$percent%',
                style: GoogleFonts.inter(
                  color: AppColors.primaryTeal,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Downloading...',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$percent% complete',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRetrySection(BoardNotification notification, bool isDark) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Download failed. Tap to retry.',
            style: GoogleFonts.inter(
              color: Colors.redAccent,
              fontSize: 14,
            ),
          ),
        ),
        Icon(
          Icons.refresh_rounded,
          color: Colors.white54,
          size: 20,
        ),
      ],
    );
  }
}
