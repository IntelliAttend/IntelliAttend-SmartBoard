class NotificationEvent {
  final String eventId;
  final String eventType;
  final int version;
  final String institutionId;
  final DateTime timestamp;
  final NotificationPayload payload;

  NotificationEvent({
    required this.eventId,
    required this.eventType,
    required this.version,
    required this.institutionId,
    required this.timestamp,
    required this.payload,
  });

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    final payload = NotificationPayload.fromJson(
        json['payload'] as Map<String, dynamic>);
    return NotificationEvent(
      eventId: json['event_id'] as String? ?? '',
      eventType: json['event_type'] as String? ?? 'notification',
      version: json['version'] as int? ?? 1,
      institutionId: json['institution_id'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      payload: payload,
    );
  }
}

class NotificationPayload {
  final String notificationId;
  final int version;
  final String priority;
  final String notificationType;
  final String displayMode;
  final int? severity;
  final String? title;
  final String? body;
  final bool requiresAcknowledgement;
  final int? durationSeconds;
  final Map<String, dynamic>? data;

  // Attachment info carried in the optional 'data' map
  String? get attachmentUrl =>
      data?['attachment_url'] as String?;
  String? get attachmentName =>
      data?['attachment_name'] as String?;
  String? get attachmentType =>
      data?['attachment_type'] as String?;
  int? get attachmentSize =>
      data?['attachment_size'] as int?;

  NotificationPayload({
    required this.notificationId,
    required this.version,
    required this.priority,
    required this.notificationType,
    required this.displayMode,
    this.severity,
    this.title,
    this.body,
    this.requiresAcknowledgement = false,
    this.durationSeconds,
    this.data,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) {
    return NotificationPayload(
      notificationId: json['notification_id'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      priority: json['priority'] as String? ?? 'P3',
      notificationType: json['notification_type'] as String? ?? 'info',
      displayMode: json['display_mode'] as String? ?? 'default',
      severity: json['severity'] as int?,
      title: json['title'] as String?,
      body: json['body'] as String?,
      requiresAcknowledgement: json['requires_acknowledgement'] == true,
      durationSeconds: json['duration_seconds'] as int?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  static const String displayModeFullScreen = 'full_screen';
  static const String displayModeOverlay = 'overlay';
  static const String displayModeReminder = 'reminder';
  static const String displayModeDefault = 'default';

  static const String notificationTypeAllClear = 'all_clear';
  static const String notificationTypeEmergency = 'emergency';
  static const String notificationTypeAlert = 'alert';
  static const String notificationTypeWarning = 'warning';
  static const String notificationTypeSystem = 'system';
  static const String notificationTypeAttendance = 'attendance';
  static const String notificationTypeMessage = 'message';
  static const String notificationTypeInfo = 'info';

  bool get isAllClear =>
      notificationType == notificationTypeAllClear &&
      displayMode == displayModeFullScreen;
}
