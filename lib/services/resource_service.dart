import '../core/utils/logger.dart';
import '../models/board_notification.dart';
import 'api_service.dart';
import 'notification_listener_service.dart';

class ResourceService {
  ResourceService._();

  /// Fetch faculty's personal resources from R2 via the backend API.
  /// Returns typed [BoardNotification] objects ready for the workspace UI.
  static Future<List<BoardNotification>> getMyResources({
    required String sessionId,
    String? sectionId,
    String? courseName,
  }) async {
    try {
      final raw = await ApiService.getMyResources(
        sessionId: sessionId,
        sectionId: sectionId,
        courseName: courseName,
      );
      return raw.mapIndexed((i, map) =>
          NotificationListenerService.fromMap('my-resource-$i', map)).toList();
    } catch (e) {
      Log.e('[ResourceService] Failed to fetch my resources: $e');
      return [];
    }
  }

  /// Fetch college-wide resources from R2 via the backend API.
  static Future<List<BoardNotification>> getCollegeResources({
    String? courseName,
  }) async {
    try {
      final raw = await ApiService.getCollegeResources(
        courseName: courseName,
      );
      return raw.mapIndexed((i, map) =>
          NotificationListenerService.fromMap('college-resource-$i', map)).toList();
    } catch (e) {
      Log.e('[ResourceService] Failed to fetch college resources: $e');
      return [];
    }
  }
}

extension _MapIndexed<T> on List<T> {
  List<R> mapIndexed<R>(R Function(int index, T item) convert) {
    final result = <R>[];
    for (var i = 0; i < length; i++) {
      result.add(convert(i, this[i]));
    }
    return result;
  }
}
