import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'IntelliAttend SmartBoard',
      appUserModelId: 'IntelliAttend.SmartBoard',
      guid: '14e9421f-33e0-43a8-8e4d-9b708d8ab4e2',
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      windows: initializationSettingsWindows,
    );

    await _notifications.initialize(settings: initializationSettings);
    Log.i('🔔 [Notification] Initialized.');
  }

  static Future<void> showWarning(String title, String body) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'smartboard_channel',
        'SmartBoard Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
      macOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
