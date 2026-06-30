import 'notification_event.dart';
import '../services/time_sync_service.dart';

enum NotificationPriority {
  emergency,
  high,
  normal,
  low,
}

class BoardNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool read;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;
  final NotificationPriority priority;
  final List<String>? precautionarySteps;
  final String? location;
  final String? safeExit;
  final String? assemblyPoint;

  final String? notificationId;
  final bool requiresAcknowledgement;
  final int? durationSeconds;
  final String? displayMode;

  BoardNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.read = false,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentType,
    this.attachmentSize,
    this.priority = NotificationPriority.low,
    this.precautionarySteps,
    this.location,
    this.safeExit,
    this.assemblyPoint,
    this.notificationId,
    this.requiresAcknowledgement = false,
    this.durationSeconds,
    this.displayMode,
  });

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;

  String get displayAttachmentName {
    if (attachmentName != null && attachmentName!.isNotEmpty) return attachmentName!;
    if (attachmentUrl != null) {
      final segments = attachmentUrl!.split('/');
      return segments.last;
    }
    return 'document';
  }

  bool get isAllClear =>
      displayMode == NotificationPayload.displayModeFullScreen &&
      type == NotificationPayload.notificationTypeAllClear;

  factory BoardNotification.fromNotificationPayload(NotificationPayload payload, {DateTime? timestamp}) {
    return BoardNotification(
      id: payload.notificationId,
      title: payload.title ?? '',
      body: payload.body ?? '',
      type: payload.notificationType,
      timestamp: timestamp ?? TimeSyncService.timeNow,
      priority: _mapDisplayModeToPriority(payload.displayMode),
      attachmentUrl: payload.attachmentUrl,
      attachmentName: payload.attachmentName,
      attachmentType: payload.attachmentType,
      attachmentSize: payload.attachmentSize,
      notificationId: payload.notificationId,
      requiresAcknowledgement: payload.requiresAcknowledgement,
      durationSeconds: payload.durationSeconds,
      displayMode: payload.displayMode,
    );
  }

  static NotificationPriority _mapDisplayModeToPriority(String displayMode) {
    if (displayMode == NotificationPayload.displayModeFullScreen) {
      return NotificationPriority.emergency;
    }
    if (displayMode == NotificationPayload.displayModeOverlay) {
      return NotificationPriority.high;
    }
    if (displayMode == NotificationPayload.displayModeReminder) {
      return NotificationPriority.normal;
    }
    return NotificationPriority.low;
  }
}
