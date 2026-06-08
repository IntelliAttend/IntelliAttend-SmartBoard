import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/config/firestore_schema.dart';
import '../core/security/firebase_rest_auth.dart';
import '../core/utils/logger.dart';

/// Lightweight Firestore REST client — replaces the `cloud_firestore` plugin
/// for the SmartBoard's read-only access patterns. The plugin internally
/// requires `firebase_auth` to fetch ID tokens, and `firebase_auth`'s Windows
/// native layer aborts the process when its listeners fire on worker
/// threads. By talking to Firestore's HTTPS REST API directly we eliminate
/// both plugins from the runtime.
///
/// Supported operations (the SmartBoard's actual needs):
///
///   * [runQuery] — structured query against a collection with an `AND`
///     filter on equality fields. Returns plain Dart maps.
///   * [getDocument] — single document fetch by path. Returns plain Dart
///     map or `null` if the document does not exist.
///
/// Writes are intentionally NOT exposed here — every state-changing path on
/// the SmartBoard goes through the server's REST contract, never directly
/// to Firestore. That keeps Firestore security rules tight (read-only for
/// this device).
class FirestoreRestClient {
  static final http.Client _client = http.Client();

  static String get _projectId => AppConfig.firebaseProjectId;

  static String get _base =>
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/(default)/documents';

  // ─── Single-document read ────────────────────────────────────────────────

  /// Fetches a single document. [docPath] is the relative path under the
  /// database root, e.g. `ActiveSessions/abc123` or
  /// `timetable_slots/slot_xyz`. Returns the flattened field map (typed
  /// values unwrapped) or `null` if the document does not exist.
  static Future<Map<String, dynamic>?> getDocument(String docPath) async {
    final token = await FirebaseRestAuth.getIdToken();
    if (token == null) {
      Log.w('[FirestoreRest] getDocument($docPath): no ID token.');
      return null;
    }

    final uri = Uri.parse('$_base/$docPath');
    try {
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        Log.w('[FirestoreRest] getDocument($docPath) '
            '${response.statusCode}: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = data['fields'] as Map<String, dynamic>?;
      if (fields == null) return null;
      final flat = _flattenFields(fields);
      // Inject the document ID (last path segment) so callers can use it.
      flat[FirestoreSchema.fieldDocId] = docPath.split('/').last;
      return flat;
    } catch (e) {
      Log.w('[FirestoreRest] getDocument($docPath) error: $e');
      return null;
    }
  }

  // ─── Collection query (AND-only equality filters) ───────────────────────

  /// Runs a structured query against [collection]. [where] is an equality
  /// filter (`field == value` for each entry, combined with AND). Optional
  /// [limit] caps the number of returned documents.
  ///
  /// Returns a list of flattened-field maps; each map contains a synthetic
  /// `__id` key with the Firestore document ID. Returns an empty list on
  /// transport errors (callers should still emit an empty list rather than
  /// blocking the stream).
  static Future<List<Map<String, dynamic>>> runQuery({
    required String collection,
    Map<String, dynamic> where = const {},
    int? limit,
  }) async {
    final token = await FirebaseRestAuth.getIdToken();
    if (token == null) {
      Log.w('[FirestoreRest] runQuery($collection): no ID token.');
      return const [];
    }

    final uri = Uri.parse('$_base:runQuery');

    final filters = where.entries.map((e) => {
      'fieldFilter': {
        'field': {'fieldPath': e.key},
        'op': 'EQUAL',
        'value': _wrapValue(e.value),
      },
    }).toList();

    final query = <String, dynamic>{
      'from': [
        {'collectionId': collection},
      ],
    };
    if (filters.length == 1) {
      query['where'] = filters.first;
    } else if (filters.length > 1) {
      query['where'] = {
        'compositeFilter': {
          'op': 'AND',
          'filters': filters,
        },
      };
    }
    if (limit != null) query['limit'] = limit;

    final body = jsonEncode({'structuredQuery': query});

    try {
      final response = await _client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        Log.w('[FirestoreRest] runQuery($collection) '
            '${response.statusCode}: ${response.body}');
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final out = <Map<String, dynamic>>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final doc = entry['document'] as Map<String, dynamic>?;
        if (doc == null) continue;
        final fields = doc['fields'] as Map<String, dynamic>? ?? const {};
        final flat = _flattenFields(fields);
        // Firestore returns the document's resource name like
        // `projects/.../documents/<collection>/<id>` — peel off just the ID.
        final name = doc['name']?.toString() ?? '';
        flat[FirestoreSchema.fieldDocId] = name.split('/').last;
        out.add(flat);
      }
      return out;
    } catch (e) {
      Log.w('[FirestoreRest] runQuery($collection) error: $e');
      return const [];
    }
  }

  // ─── Typed-value helpers ─────────────────────────────────────────────────

  /// Recursively unwraps Firestore's typed value representation:
  ///   {"stringValue": "x"}     → "x"
  ///   {"integerValue": "5"}   → 5
  ///   {"doubleValue": 3.14}   → 3.14
  ///   {"booleanValue": true}  → true
  ///   {"timestampValue": "."} → DateTime
  ///   {"arrayValue": {"values": [...]}}  → `List<dynamic>`
  ///   {"mapValue":   {"fields": {...}}}  → `Map<String, dynamic>`
  ///   {"nullValue":  ...}                → null
  static Map<String, dynamic> _flattenFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final entry in fields.entries) {
      out[entry.key] = _unwrap(entry.value);
    }
    return out;
  }

  static dynamic _unwrap(dynamic typed) {
    if (typed is! Map<String, dynamic>) return typed;
    if (typed.containsKey('stringValue')) return typed['stringValue'];
    if (typed.containsKey('integerValue')) {
      final v = typed['integerValue'];
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    if (typed.containsKey('doubleValue')) {
      final v = typed['doubleValue'];
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    if (typed.containsKey('booleanValue')) return typed['booleanValue'] == true;
    if (typed.containsKey('nullValue')) return null;
    if (typed.containsKey('timestampValue')) {
      return DateTime.tryParse(typed['timestampValue'].toString());
    }
    if (typed.containsKey('arrayValue')) {
      final values =
          (typed['arrayValue']?['values'] as List?) ?? const <dynamic>[];
      return values.map(_unwrap).toList();
    }
    if (typed.containsKey('mapValue')) {
      final inner =
          typed['mapValue']?['fields'] as Map<String, dynamic>? ?? const {};
      return _flattenFields(inner);
    }
    return null;
  }

  /// Wraps a Dart value into the Firestore typed-value form used in filter
  /// expressions. Supported types: String, int, double, bool, null.
  static Map<String, dynamic> _wrapValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is String) return {'stringValue': v};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': v.toString()};
    if (v is double) return {'doubleValue': v};
    // Fallback — stringify and treat as a string filter.
    return {'stringValue': v.toString()};
  }
}
