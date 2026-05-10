import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/logger.dart';

/// Lightweight feature-flag provider backed by a single Firestore document.
///
/// Reads `config/feature_flags` and caches the map in memory. Refreshes
/// every [refreshInterval]. On failure (no network, Firestore down) the
/// last known values are preserved — the SmartBoard never blocks on config.
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  static const String _collection = 'config';
  static const String _document = 'feature_flags';
  static const Duration refreshInterval = Duration(minutes: 5);

  Map<String, dynamic> _flags = {};
  Timer? _refreshTimer;
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await _fetch();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => _fetch());
    _initialized = true;
    Log.i('[RemoteConfig] Initialized with ${_flags.length} flags');
  }

  Future<void> _fetch() async {
    try {
      final doc = FirebaseFirestore.instance
          .collection(_collection)
          .doc(_document);
      final snapshot = await doc.get();
      if (snapshot.exists) {
        _flags = Map<String, dynamic>.from(snapshot.data() ?? {});
      }
    } catch (e) {
      Log.w('[RemoteConfig] Fetch failed, using cached values: $e');
    }
  }

  bool getBool(String key, {bool defaultValue = false}) =>
      _flags[key] is bool ? _flags[key] as bool : defaultValue;

  String getString(String key, {String defaultValue = ''}) =>
      _flags[key] is String ? _flags[key] as String : defaultValue;

  int getInt(String key, {int defaultValue = 0}) =>
      _flags[key] is int ? _flags[key] as int : defaultValue;

  double getDouble(String key, {double defaultValue = 0.0}) =>
      _flags[key] is num ? (_flags[key] as num).toDouble() : defaultValue;

  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _initialized = false;
  }
}
