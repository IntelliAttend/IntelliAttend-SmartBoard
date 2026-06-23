import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';

import 'package:intelliattend_smartboard/main.dart';
import 'package:intelliattend_smartboard/data/repositories/device_repository.dart';
import 'package:intelliattend_smartboard/data/repositories/auth_repository.dart';
import 'package:intelliattend_smartboard/models/isar_schemas.dart';
import 'package:intelliattend_smartboard/presentation/providers/registration_provider.dart';

class _MockDeviceRepository implements IDeviceRepository {
  @override Future<bool> isRegistered() async => false;
  @override Future<DeviceRegistration?> getRegistration() async => null;
  @override Future<void> clearRegistration() async {}
  @override Future<void> performMigrationBridge() async {}
  @override Future<void> sendHeartbeat({required String smartBoardId, required String hardwareId, required String screenState, required int uptimeSeconds, required String appVersion}) async {}
  @override Future<void> syncTimetable({bool fullSync = false}) async {}
  @override Future<List<TimetableEntry>> getTodayTimeline() async => [];
  @override Future<List<TimetableEntry>> getWeeklyTimeline() async => [];
  @override Future<TimetableEntry?> getCurrentSlot() async => null;
}

class _MockAuthRepository implements IAuthRepository {
  @override Future<Map<String, dynamic>?> login(String boardId, String password) async => null;
  @override Future<Map<String, dynamic>?> initiateRegistration(String boardId, String password) async => null;
  @override Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async => null;
  @override Future<Map<String, dynamic>?> completeRegistration(String boardId, String hardwareId, String verificationToken) async => null;
  @override Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar, {String? hardwareId}) async {}
  @override Future<void> logout() async {}
}

Widget createTestApp() {
  final deviceRepo = _MockDeviceRepository();
  final authRepo = _MockAuthRepository();
  return MultiProvider(
    providers: [
      Provider<IDeviceRepository>.value(value: deviceRepo),
      Provider<IAuthRepository>.value(value: authRepo),
      ChangeNotifierProvider(create: (_) => RegistrationProvider(authRepo, deviceRepo)),
    ],
    child: const IntelliAttendApp(),
  );
}

void main() {
  testWidgets('IntelliAttendApp renders with providers', (WidgetTester tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
