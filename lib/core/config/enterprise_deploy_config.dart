import 'dart:convert';
import 'dart:io';

import '../utils/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EnterpriseDeployConfig
//
// Structured representation of an enterprise deployment configuration.
// IT admins create this file before deployment; the validator checks it
// before the MSI runs; the app reads it at startup.
//
// Config resolution priority (unchanged):
//   1. Config\deploy_config.json  (NEW — structured, validated)
//   2. Config\env.json            (existing — KEY=VALUE)
//   3. Config\.env                (legacy)
//   4. --dart-define              (compile-time)
//   5. Hardcoded defaults         (production fallback)
//
// ─────────────────────────────────────────────────────────────────────────────
class EnterpriseDeployConfig {
  /// Unique SmartBoard identifier (e.g. "IASB-4208").
  final String boardId;

  /// Server configuration.
  final ServerConfig server;

  /// Firebase configuration.
  final FirebaseConfig firebase;

  /// Update policy.
  final UpdateConfig update;

  /// Feature flags.
  final FeatureConfig features;

  /// Physical location metadata (for fleet identification and Sentry tagging).
  final LocationConfig? location;

  /// Deployment metadata (for IT tracking).
  final DeploymentMetadata? deployment;

  const EnterpriseDeployConfig({
    required this.boardId,
    required this.server,
    this.firebase = const FirebaseConfig(),
    this.update = const UpdateConfig(),
    this.features = const FeatureConfig(),
    this.location,
    this.deployment,
  });

  /// Parse from a JSON map.
  factory EnterpriseDeployConfig.fromJson(Map<String, dynamic> json) {
    return EnterpriseDeployConfig(
      boardId: json['board_id']?.toString() ?? '',
      server: ServerConfig.fromJson(
        Map<String, dynamic>.from(json['server'] as Map? ?? {}),
      ),
      firebase: FirebaseConfig.fromJson(
        Map<String, dynamic>.from(json['firebase'] as Map? ?? {}),
      ),
      update: UpdateConfig.fromJson(
        Map<String, dynamic>.from(json['update'] as Map? ?? {}),
      ),
      features: FeatureConfig.fromJson(
        Map<String, dynamic>.from(json['features'] as Map? ?? {}),
      ),
      location: json['location'] != null
          ? LocationConfig.fromJson(
              Map<String, dynamic>.from(json['location'] as Map),
            )
          : null,
      deployment: json['deployment'] != null
          ? DeploymentMetadata.fromJson(
              Map<String, dynamic>.from(json['deployment'] as Map),
            )
          : null,
    );
  }

  /// Load from a file path.
  static Future<EnterpriseDeployConfig?> loadFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return EnterpriseDeployConfig.fromJson(json);
    } catch (e) {
      Log.e('[DeployConfig] Failed to load from $path: $e');
      return null;
    }
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() => {
        'board_id': boardId,
        'server': server.toJson(),
        'firebase': firebase.toJson(),
        'update': update.toJson(),
        'features': features.toJson(),
        if (location != null) 'location': location!.toJson(),
        if (deployment != null) 'deployment': deployment!.toJson(),
      };

  /// Convert to env.json format (KEY=VALUE lines) for backward compatibility.
  String toEnvFormat() {
    final lines = <String>[
      'API_BASE_URL=${server.apiBaseUrl}',
      'FIREBASE_API_KEY=${firebase.apiKey}',
      'FIREBASE_PROJECT_ID=${firebase.projectId}',
      'FIREBASE_APP_ID=${firebase.appId}',
      'FIREBASE_MESSAGING_SENDER_ID=${firebase.messagingSenderId}',
      if (server.sslPinFingerprint != null)
        'SSL_PIN_FINGERPRINT=${server.sslPinFingerprint}',
      'ENABLE_DOCUMENTS=${features.enableDocuments}',
      'DEBUG=false',
    ];
    return lines.join('\n');
  }
}

// ── Sub-configs ────────────────────────────────────────────────────────────

class ServerConfig {
  final String apiBaseUrl;
  final String? sslPinFingerprint;

  const ServerConfig({
    this.apiBaseUrl = 'https://api.intelliattend.app',
    this.sslPinFingerprint,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      apiBaseUrl: json['api_base_url']?.toString() ??
          'https://api.intelliattend.app',
      sslPinFingerprint: json['ssl_pin_fingerprint']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'api_base_url': apiBaseUrl,
        if (sslPinFingerprint != null) 'ssl_pin_fingerprint': sslPinFingerprint,
      };
}

class FirebaseConfig {
  final String apiKey;
  final String projectId;
  final String appId;
  final String messagingSenderId;

  const FirebaseConfig({
    this.apiKey = 'AIzaSyBooFadQf3TZFvZOUJkihMUdgexrbeoQnE',
    this.projectId = 'intelliattend-a2564',
    this.appId = '1:738499328288:web:c345f44de9d8393062ff45',
    this.messagingSenderId = '738499328288',
  });

  factory FirebaseConfig.fromJson(Map<String, dynamic> json) {
    return FirebaseConfig(
      apiKey: json['api_key']?.toString() ??
          'AIzaSyBooFadQf3TZFvZOUJkihMUdgexrbeoQnE',
      projectId: json['project_id']?.toString() ?? 'intelliattend-a2564',
      appId: json['app_id']?.toString() ??
          '1:738499328288:web:c345f44de9d8393062ff45',
      messagingSenderId:
          json['messaging_sender_id']?.toString() ?? '738499328288',
    );
  }

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'project_id': projectId,
        'app_id': appId,
        'messaging_sender_id': messagingSenderId,
      };
}

class UpdateConfig {
  final String channel;
  final bool autoUpdate;
  final String? hmacSecretKey;

  const UpdateConfig({
    this.channel = 'stable',
    this.autoUpdate = true,
    this.hmacSecretKey,
  });

  factory UpdateConfig.fromJson(Map<String, dynamic> json) {
    return UpdateConfig(
      channel: json['channel']?.toString() ?? 'stable',
      autoUpdate: json['auto_update'] != false,
      hmacSecretKey: json['hmac_secret_key']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'auto_update': autoUpdate,
        if (hmacSecretKey != null) 'hmac_secret_key': hmacSecretKey,
      };
}

class FeatureConfig {
  final bool enableDocuments;
  final bool enableVideoBreaks;
  final bool kioskMode;

  const FeatureConfig({
    this.enableDocuments = true,
    this.enableVideoBreaks = false,
    this.kioskMode = true,
  });

  factory FeatureConfig.fromJson(Map<String, dynamic> json) {
    return FeatureConfig(
      enableDocuments: json['enable_documents'] != false,
      enableVideoBreaks: json['enable_video_breaks'] == true,
      kioskMode: json['kiosk_mode'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'enable_documents': enableDocuments,
        'enable_video_breaks': enableVideoBreaks,
        'kiosk_mode': kioskMode,
      };
}

class LocationConfig {
  /// School or institution name (e.g. "MRCET").
  final String? school;

  /// Building or block identifier (e.g. "Block A").
  final String? building;

  /// Room or lab identifier (e.g. "A-204").
  final String? room;

  const LocationConfig({
    this.school,
    this.building,
    this.room,
  });

  factory LocationConfig.fromJson(Map<String, dynamic> json) {
    return LocationConfig(
      school: json['school']?.toString(),
      building: json['building']?.toString(),
      room: json['room']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (school != null) 'school': school,
        if (building != null) 'building': building,
        if (room != null) 'room': room,
      };
}

class DeploymentMetadata {
  /// Globally unique deployment identifier (e.g. "mrcet-prod", "customer-001").
  /// Used for cross-customer fleet filtering in Sentry.
  final String? deploymentId;

  /// Name or ID of the IT admin who deployed this board.
  final String? deployedBy;

  /// ISO-8601 timestamp of deployment.
  final String? deployedAt;

  /// Physical location (building, floor, room).
  final String? site;

  /// Academic department.
  final String? department;

  /// Free-text deployment notes.
  final String? notes;

  const DeploymentMetadata({
    this.deploymentId,
    this.deployedBy,
    this.deployedAt,
    this.site,
    this.department,
    this.notes,
  });

  factory DeploymentMetadata.fromJson(Map<String, dynamic> json) {
    return DeploymentMetadata(
      deploymentId: json['deployment_id']?.toString(),
      deployedBy: json['deployed_by']?.toString(),
      deployedAt: json['deployed_at']?.toString(),
      site: json['site']?.toString(),
      department: json['department']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (deploymentId != null) 'deployment_id': deploymentId,
        if (deployedBy != null) 'deployed_by': deployedBy,
        if (deployedAt != null) 'deployed_at': deployedAt,
        if (site != null) 'site': site,
        if (department != null) 'department': department,
        if (notes != null) 'notes': notes,
      };
}
