/// Resource item returned by the server's ResourceItem schema.
///
/// Matches `backend/app/modules/resources/schemas.py::ResourceItem`.
class ResourceItem {
  final String id;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String scope;
  final String securityStatus;
  final bool isActive;
  final String? subjectCode;
  final List<String> allowedSections;
  final String? createdAt;

  const ResourceItem({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.scope,
    required this.securityStatus,
    required this.isActive,
    this.subjectCode,
    this.allowedSections = const [],
    this.createdAt,
  });

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      id: json['id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? 'unknown',
      fileSize: _parseInt(json['file_size']),
      mimeType: json['mime_type']?.toString() ?? 'application/octet-stream',
      scope: json['scope']?.toString() ?? 'college_shared',
      securityStatus: json['security_status']?.toString() ?? 'PENDING',
      isActive: json['is_active'] == true,
      subjectCode: json['subject_code']?.toString(),
      allowedSections: (json['allowed_sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: json['created_at']?.toString(),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Human-readable file size (e.g. "2.4 MB").
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// File extension in lowercase (e.g. "pdf").
  String get fileExtension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  bool get isPdf => fileExtension == 'pdf';
  bool get isPowerPoint =>
      fileExtension == 'ppt' || fileExtension == 'pptx';
  bool get isWord =>
      fileExtension == 'doc' || fileExtension == 'docx';
  bool get isSpreadsheet =>
      fileExtension == 'xls' || fileExtension == 'xlsx';
  bool get isImage =>
      fileExtension == 'png' ||
      fileExtension == 'jpg' ||
      fileExtension == 'jpeg' ||
      fileExtension == 'gif';

  /// Whether this resource is college-shared (visible to all faculty).
  bool get isCollegeShared => scope == 'college_shared';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
