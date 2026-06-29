import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/models/notification_event.dart';
import 'package:intelliattend_smartboard/services/notification_listener_service.dart';

void main() {
  // ── NotificationEvent model ────────────────────────────────────────

  group('NotificationEvent', () {
    test('parses full notification event from JSON', () {
      final json = {
        'event_id': 'evt_001',
        'event_type': 'notification',
        'timestamp': '2026-06-26T10:30:00Z',
        'payload': {
          'notification_id': 'nid_001',
          'title': 'Test Alert',
          'body': 'This is a test',
          'notification_type': 'emergency',
          'display_mode': 'full_screen',
          'duration_seconds': 30,
          'requires_acknowledgement': true,
        },
      };

      final event = NotificationEvent.fromJson(json);

      expect(event.eventId, equals('evt_001'));
      expect(event.eventType, equals('notification'));
      expect(event.timestamp, isNotNull);
      expect(event.payload.notificationId, equals('nid_001'));
      expect(event.payload.title, equals('Test Alert'));
      expect(event.payload.displayMode, equals(NotificationPayload.displayModeFullScreen));
      expect(event.payload.durationSeconds, equals(30));
      expect(event.payload.requiresAcknowledgement, isTrue);
    });

    test('handles missing optional payload fields', () {
      final json = {
        'event_id': 'evt_002',
        'event_type': 'notification',
        'payload': {
          'notification_id': 'nid_002',
        },
      };

      final event = NotificationEvent.fromJson(json);

      expect(event.eventId, equals('evt_002'));
      expect(event.payload.notificationId, equals('nid_002'));
      expect(event.payload.title, isNull);
      expect(event.payload.body, isNull);
      expect(event.payload.displayMode, equals('default'));
      expect(event.payload.durationSeconds, isNull);
      expect(event.payload.requiresAcknowledgement, isFalse);
    });

    test('isAllClear returns true for full_screen + all_clear', () {
      final payload = NotificationPayload(
        notificationId: 'nid_003',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: NotificationPayload.notificationTypeAllClear,
      );

      expect(payload.isAllClear, isTrue);
    });

    test('isAllClear returns false for other combinations', () {
      final fsEmergency = NotificationPayload(
        notificationId: 'nid_004',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: 'emergency',
      );
      expect(fsEmergency.isAllClear, isFalse);

      final overlayAllClear = NotificationPayload(
        notificationId: 'nid_005',
        version: 1,
        priority: 'P3',
        displayMode: NotificationPayload.displayModeOverlay,
        notificationType: NotificationPayload.notificationTypeAllClear,
      );
      expect(overlayAllClear.isAllClear, isFalse);
    });
  });

  // ── BoardNotification model ───────────────────────────────────────

  group('BoardNotification', () {
    test('fromNotificationPayload maps full_screen to emergency priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_010',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: 'emergency',
        title: 'Fire',
        body: 'Evacuate',
      );

      final n = BoardNotification.fromNotificationPayload(payload);

      expect(n.priority, equals(NotificationPriority.emergency));
      expect(n.notificationId, equals('nid_010'));
      expect(n.displayMode, equals(NotificationPayload.displayModeFullScreen));
      expect(n.title, equals('Fire'));
      expect(n.body, equals('Evacuate'));
    });

    test('fromNotificationPayload maps overlay to high priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_011',
        version: 1,
        priority: 'P1',
        displayMode: NotificationPayload.displayModeOverlay,
        notificationType: 'alert',
      );

      final n = BoardNotification.fromNotificationPayload(payload);

      expect(n.priority, equals(NotificationPriority.high));
    });

    test('fromNotificationPayload maps reminder to normal priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_012',
        version: 1,
        priority: 'P2',
        displayMode: NotificationPayload.displayModeReminder,
        notificationType: 'info',
      );

      final n = BoardNotification.fromNotificationPayload(payload);

      expect(n.priority, equals(NotificationPriority.normal));
    });

    test('fromNotificationPayload maps default to low priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_013',
        version: 1,
        priority: 'P3',
        displayMode: NotificationPayload.displayModeDefault,
        notificationType: 'info',
      );

      final n = BoardNotification.fromNotificationPayload(payload);

      expect(n.priority, equals(NotificationPriority.low));
    });

    test('isAllClear detects full_screen + all_clear', () {
      final n = BoardNotification(
        id: 'test',
        title: 'All Clear',
        body: 'Emergency resolved',
        type: NotificationPayload.notificationTypeAllClear,
        timestamp: DateTime.now(),
        priority: NotificationPriority.emergency,
        displayMode: NotificationPayload.displayModeFullScreen,
      );

      expect(n.isAllClear, isTrue);
    });

    test('isAllClear is false for emergency without all_clear type', () {
      final n = BoardNotification(
        id: 'test',
        title: 'Emergency',
        body: 'Fire',
        type: 'emergency',
        timestamp: DateTime.now(),
        priority: NotificationPriority.emergency,
        displayMode: NotificationPayload.displayModeFullScreen,
      );

      expect(n.isAllClear, isFalse);
    });
  });

  // ── NotificationListenerService ───────────────────────────────────

  group('NotificationListenerService', () {
    late NotificationListenerService service;

    setUp(() {
      service = NotificationListenerService();
    });

    test('handleNotificationEvent deduplicates by event_id', () {
      final payload = NotificationPayload(
        notificationId: 'nid_020',
        version: 1,
        priority: 'P3',
        displayMode: NotificationPayload.displayModeDefault,
        notificationType: 'info',
        title: 'Test',
      );
      final event = NotificationEvent(
        eventId: 'evt_020',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      service.handleNotificationEvent(event);
      expect(service.bellNotifications.length, equals(1));

      service.handleNotificationEvent(event);
      expect(service.bellNotifications.length, equals(1),
          reason: 'Duplicate event_id should be skipped');
    });

    test('handleNotificationEvent skips dismissed notification_id', () async {
      final payload = NotificationPayload(
        notificationId: 'nid_021',
        version: 1,
        priority: 'P3',
        displayMode: NotificationPayload.displayModeDefault,
        notificationType: 'info',
        title: 'Should be skipped',
      );
      final event = NotificationEvent(
        eventId: 'evt_021_unique',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      await service.dismissNotification('nid_021');
      expect(service.bellNotifications.where((n) => n.notificationId == 'nid_021'), isEmpty);

      service.handleNotificationEvent(event);
      expect(service.bellNotifications.where((n) => n.notificationId == 'nid_021'), isEmpty,
          reason: 'Previously dismissed notification should not be re-added');
    });

    test('handleNotificationEvent emits on onAllClear for all_clear payload', () async {
      final payload = NotificationPayload(
        notificationId: 'nid_022',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: NotificationPayload.notificationTypeAllClear,
      );
      final event = NotificationEvent(
        eventId: 'evt_022',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      final allClearFuture = service.onAllClear.first;
      service.handleNotificationEvent(event);
      final received = await allClearFuture;

      expect(received, isNotNull);
      expect(received.isAllClear, isTrue);
    });

    test('handleNotificationEvent routes full_screen to emergency priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_023',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: 'emergency',
        title: 'Fire Drill',
      );
      final event = NotificationEvent(
        eventId: 'evt_023',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      service.handleNotificationEvent(event);

      final emergencyList = service.emergencyNotifications;
      expect(emergencyList.length, equals(1));
      expect(emergencyList.first.title, equals('Fire Drill'));
    });

    test('handleNotificationEvent routes overlay to high priority', () {
      final payload = NotificationPayload(
        notificationId: 'nid_024',
        version: 1,
        priority: 'P1',
        displayMode: NotificationPayload.displayModeOverlay,
        notificationType: 'alert',
        title: 'Urgent Alert',
      );
      final event = NotificationEvent(
        eventId: 'evt_024',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      service.handleNotificationEvent(event);

      final highList = service.highPriorityNotifications;
      expect(highList.length, equals(1));
      expect(highList.first.title, equals('Urgent Alert'));
    });

    test('handleNotificationEvent routes reminder to normal priority', () async {
      final payload = NotificationPayload(
        notificationId: 'nid_025',
        version: 1,
        priority: 'P2',
        displayMode: NotificationPayload.displayModeReminder,
        notificationType: 'info',
        title: 'Library Reminder',
      );
      final event = NotificationEvent(
        eventId: 'evt_025',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      final arrivedFuture = service.onNotificationArrived.first;
      service.handleNotificationEvent(event);
      final arrived = await arrivedFuture;

      expect(arrived.title, equals('Library Reminder'));
      expect(arrived.priority, equals(NotificationPriority.normal));
    });

    test('handleNotificationEvent routes default to inbox only (no incoming)', () async {
      // Set up a listener that will capture if anything arrives
      final hasEvent = Future.any([
        service.onNotificationArrived.first.then((_) => true),
        Future.delayed(const Duration(milliseconds: 100), () => false),
      ]);

      final payload = NotificationPayload(
        notificationId: 'nid_026',
        version: 1,
        priority: 'P3',
        displayMode: NotificationPayload.displayModeDefault,
        notificationType: 'info',
        title: 'Campus Notice',
      );
      final event = NotificationEvent(
        eventId: 'evt_026',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      service.handleNotificationEvent(event);

      // Should NOT emit on incoming stream
      expect(await hasEvent, isFalse);
      // But should be in the cache
      expect(service.bellNotifications.any((n) => n.title == 'Campus Notice'), isTrue);
    });

    test('dismissNotification adds to dismissed set and removes from cache', () async {
      // First add a notification via handleNotificationEvent
      final payload = NotificationPayload(
        notificationId: 'nid_027',
        version: 1,
        priority: 'P0',
        displayMode: NotificationPayload.displayModeFullScreen,
        notificationType: 'emergency',
        title: 'Dismiss Me',
      );
      final event = NotificationEvent(
        eventId: 'evt_027',
        eventType: 'notification',
        version: 1,
        institutionId: 'inst_001',
        timestamp: DateTime.now(),
        payload: payload,
      );

      service.handleNotificationEvent(event);
      expect(service.emergencyNotifications.any((n) => n.notificationId == 'nid_027'), isTrue);

      await service.dismissNotification('nid_027');
      // Dismissed set prevents re-add
      expect(service.emergencyNotifications.any((n) => n.notificationId == 'nid_027'), isFalse);
    });

    test('reAcknowledgeDismissed iterates over dismissed IDs without throwing', () async {
      await service.dismissNotification('nid_re_001');
      await service.dismissNotification('nid_re_002');
      await service.dismissNotification('nid_re_003');

      // Should not throw; API calls will fail silently in test env
      expect(() => service.reAcknowledgeDismissed(), returnsNormally);
    });
  });
}
