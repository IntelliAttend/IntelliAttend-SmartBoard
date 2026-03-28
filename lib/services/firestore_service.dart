import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _attendanceStreamController = StreamController<Map<String, dynamic>>.broadcast();

  /// A live pipeline of successfully verified student scans.
  /// The `AttendanceScreen` can listen to this to reactively paint grid squares green.
  Stream<Map<String, dynamic>> get attendanceStream => _attendanceStreamController.stream;

  StreamSubscription? _subscription;

  /// Starts listening to a specific session's attendance collection in Firestore.
  /// Replaces the old Node.js WebSocket connection.
  void startListening(String sessionId) {
    print('[FirestoreService] Subscribing to Session: $sessionId');

    // Query: ActiveSessions/{sessionId}/Attendance
    _subscription = _db
        .collection('ActiveSessions')
        .doc(sessionId)
        .collection('Attendance')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data;
          if (data != null) {
            // Append the student_id for convenience in the UI
            final Map<String, dynamic> attendanceData = {
              'student_id': change.doc.id,
              ...data,
            };
            print('[FirestoreService] New Attendance Doc: ${change.doc.id}');
            _attendanceStreamController.add(attendanceData);
          }
        }
      }
    }, onError: (e) {
      print('[FirestoreService] Subscription Error: $e');
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _attendanceStreamController.close();
  }
}
