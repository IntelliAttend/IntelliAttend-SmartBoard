import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/board_notification.dart';
import '../../services/document_service.dart';
import 'document_viewer_screen.dart';
import 'file_viewer_screen.dart';

class NotificationDetailScreen extends StatefulWidget {
  final BoardNotification notification;

  const NotificationDetailScreen({super.key, required this.notification});

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final DocumentService _documentService = DocumentService();
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _hasError = false;

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
      case 'emergency':
        return Icons.warning_rounded;
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
      case 'emergency':
        return const Color(0xFFC72C31);
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
        return 'REMINDER';
      case NotificationPriority.low:
        return 'INFO';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final min = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} at $hour:$min $ampm';
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

  Future<void> _openAttachment() async {
    final notification = widget.notification;
    if (!mounted || !notification.hasAttachment) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _hasError = false;
    });

    final path = await _documentService.downloadDocument(
      notification.attachmentUrl!,
      notification.displayAttachmentName,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
    );

    if (!mounted) return;

    if (path == null) {
      setState(() {
        _isDownloading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _isDownloading = false;
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
      final ext = fileName.split('.').last.toLowerCase();
      if (['txt', 'md', 'log', 'csv', 'json', 'xml', 'yaml', 'yml',
            'png', 'jpg', 'jpeg', 'gif', 'webp', 'html',
            'ini', 'cfg', 'bat', 'sh', 'bmp', 'svg',
            'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext)) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FileViewerScreen(
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
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final documentsEnabled = AppConfig.enableDocuments;
    final hasDoc = documentsEnabled && notification.hasAttachment;
    final priorityColor = _colorForPriority(notification.priority);
    final showEvacDetails = notification.priority == NotificationPriority.emergency;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: Text(
          'Notification',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Priority & Type bar
            Row(
              children: [
                if (notification.priority != NotificationPriority.low)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _labelForPriority(notification.priority),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: priorityColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (notification.priority != NotificationPriority.low)
                  const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _colorForType(notification.type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForType(notification.type),
                        size: 14,
                        color: _colorForType(notification.type),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _capitalize(notification.type),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _colorForType(notification.type),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Title
            Text(
              notification.title,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
                height: 1.3,
              ),
            ),

            const SizedBox(height: 28),

            // Body
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : AppColors.bgLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.black38,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    notification.body.isNotEmpty ? notification.body : 'No additional details.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Timestamp
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_timeAgo(notification.timestamp)} \u2022 ${_formatDateTime(notification.timestamp)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),

            // Evacuation details (emergency only)
            if (showEvacDetails && (notification.location != null || notification.safeExit != null || notification.assemblyPoint != null || (notification.precautionarySteps != null && notification.precautionarySteps!.isNotEmpty))) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFC72C31).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFC72C31).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: const Color(0xFFC72C31)),
                        const SizedBox(width: 8),
                        Text(
                          'Evacuation Details',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFC72C31),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (notification.location != null) ...[
                      _evacRow('Location', notification.location!, Icons.location_on_outlined),
                      const SizedBox(height: 8),
                    ],
                    if (notification.safeExit != null) ...[
                      _evacRow('Safe Exit', notification.safeExit!, Icons.exit_to_app),
                      const SizedBox(height: 8),
                    ],
                    if (notification.assemblyPoint != null) ...[
                      _evacRow('Assembly Point', notification.assemblyPoint!, Icons.people_outline),
                      const SizedBox(height: 8),
                    ],
                    if (notification.precautionarySteps != null && notification.precautionarySteps!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Steps to follow:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFC72C31).withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final step in notification.precautionarySteps!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('\u2022 ', style: GoogleFonts.inter(color: const Color(0xFFC72C31), fontSize: 14)),
                              Expanded(
                                child: Text(
                                  step,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFFC72C31).withValues(alpha: 0.85),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],

            // Attachment
            if (hasDoc) ...[
              const SizedBox(height: 24),
              Text(
                'Attachment',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              _buildAttachmentSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _evacRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFC72C31).withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFC72C31).withValues(alpha: 0.8),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFC72C31),
            ),
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Widget _buildAttachmentSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: _isDownloading ? null : () => _openAttachment(),
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
        child: _isDownloading
            ? _buildDownloadProgress(isDark)
            : _hasError
                ? _buildRetrySection(isDark)
                : _buildAttachmentInfo(isDark),
      ),
    );
  }

  Widget _buildAttachmentInfo(bool isDark) {
    final notification = widget.notification;
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
                  style: GoogleFonts.inter(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        Icon(
          Icons.download_rounded,
          color: AppColors.primaryTeal.withValues(alpha: 0.7),
          size: 20,
        ),
      ],
    );
  }

  Widget _buildDownloadProgress(bool isDark) {
    final percent = (_downloadProgress * 100).toInt();
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _downloadProgress,
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
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
                'Loading...',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$percent% loaded',
                style: GoogleFonts.inter(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRetrySection(bool isDark) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Download failed. Tap to retry.',
            style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 14),
          ),
        ),
        Icon(Icons.refresh_rounded, color: Colors.white54, size: 20),
      ],
    );
  }
}
