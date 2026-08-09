class MediaPushEvent {
  final String sessionId;
  final String mediaUrl;
  final String mediaType;
  final int? displayDurationSeconds;

  const MediaPushEvent({
    required this.sessionId,
    required this.mediaUrl,
    required this.mediaType,
    this.displayDurationSeconds,
  });

  factory MediaPushEvent.fromJson(Map<String, dynamic> json) {
    return MediaPushEvent(
      sessionId: json['session_id'] as String? ?? '',
      mediaUrl: json['media_url'] as String? ?? '',
      mediaType: json['media_type'] as String? ?? 'image',
      displayDurationSeconds: json['display_duration_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'display_duration_seconds': displayDurationSeconds,
    };
  }
}
