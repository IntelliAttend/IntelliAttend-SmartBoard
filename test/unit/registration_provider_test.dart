import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:intelliattend_smartboard/data/repositories/auth_repository.dart';
import 'package:intelliattend_smartboard/data/repositories/device_repository.dart';
import 'package:intelliattend_smartboard/models/isar_schemas.dart';
import 'package:intelliattend_smartboard/presentation/providers/registration_provider.dart';
import 'package:intelliattend_smartboard/services/session_manager.dart';

class _MockDeviceRepository implements IDeviceRepository {
  DeviceRegistration? _registration;

  void setRegistration(DeviceRegistration? reg) => _registration = reg;

  @override Future<bool> isRegistered() async => _registration != null;
  @override Future<DeviceRegistration?> getRegistration() async => _registration;
  @override Future<void> clearRegistration() async { _registration = null; }
  @override Future<void> performMigrationBridge() async {}
  @override Future<void> sendHeartbeat({required String smartBoardId, required String hardwareId, required String screenState, required int uptimeSeconds, required String appVersion}) async {}
  @override Future<void> hydrateFromServer() async {}
  @override Future<List<TimetableEntry>> getTodayTimeline() async => [];
  @override Future<List<TimetableEntry>> getWeeklyTimeline() async => [];
  @override Future<TimetableEntry?> getCurrentSlot() async => null;
}

class _MockAuthRepository implements IAuthRepository {
  Map<String, dynamic>? _loginResult;
  Map<String, dynamic>? _initResult;
  Map<String, dynamic>? _savedProfile;
  int saveRegistrationCallCount = 0;

  void setLoginResult(Map<String, dynamic>? result) => _loginResult = result;
  void setInitResult(Map<String, dynamic>? result) => _initResult = result;
  Map<String, dynamic>? get savedProfile => _savedProfile;

  @override Future<Map<String, dynamic>?> login(String boardId, String password) async => _loginResult;
  @override Future<Map<String, dynamic>?> initiateRegistration(String boardId, String password) async => _initResult;
  @override Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async => null;
  @override Future<Map<String, dynamic>?> completeRegistration(String boardId, String hardwareId, String verificationToken, {Map<String, dynamic>? metadata}) async => null;
  @override Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar, {String? hardwareId}) async {
    _savedProfile = profile;
    saveRegistrationCallCount++;
  }
  @override Future<void> logout() async {}
}

Isar? _testIsar;

Future<void> _ensureIsar() async {
  if (_testIsar != null) return;
  try {
    final dir = Directory.systemTemp.createTempSync('isar_reg_test');
    _testIsar = await Isar.open(
      [DeviceRegistrationSchema],
      directory: dir.path,
      name: 'registration_test',
    );
    SessionManager.isarOverride = _testIsar;
  } catch (_) {
    // Isar native lib unavailable in test env — tests that need isar will skip.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Use the official setMockInitialValues API to replace the platform
  // implementation with an in-memory store — avoids MissingPluginException
  // from the real MethodChannelFlutterSecureStorage.
  FlutterSecureStorage.setMockInitialValues({});

  late _MockAuthRepository authRepo;
  late _MockDeviceRepository deviceRepo;

  setUp(() async {
    authRepo = _MockAuthRepository();
    deviceRepo = _MockDeviceRepository();
    await _ensureIsar();
  });

  group('RegistrationProvider', () {
    test('step is idle initially', () {
      final provider = RegistrationProvider(authRepo, deviceRepo);
      expect(provider.step, RegistrationStep.idle);
      provider.dispose();
    });

    test('reset clears state', () {
      final provider = RegistrationProvider(authRepo, deviceRepo);
      provider.reset();
      expect(provider.step, RegistrationStep.idle);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, false);
      provider.dispose();
    });
  });

  group('RegistrationProvider — already_registered (S5)', () {
    test('login transitions to completed when server returns already_registered', () async {
      if (_testIsar == null) return;

      authRepo.setLoginResult({
        'uid': 'test-uid',
        'email': 'admin@example.com',
        'admin_email': 'admin@example.com',
      });
      authRepo.setInitResult({
        'status': 'already_registered',
        'smart_board_id': 'IASB-4208',
        'room_id': 'R101',
        'room_name': 'Hall 1',
        'building': 'Main',
        'department': 'CS',
      });

      final reg = DeviceRegistration()
        ..smartBoardId = 'IASB-4208'
        ..hardwareId = 'HW-TEST-001'
        ..roomName = 'Hall 1'
        ..building = 'Main'
        ..department = 'CS'
        ..capacity = 60
        ..registrationDate = DateTime.now();
      deviceRepo.setRegistration(reg);

      final provider = RegistrationProvider(authRepo, deviceRepo);
      await provider.login('IASB-4208', 'test-pass');

      expect(provider.step, RegistrationStep.completed);
      expect(authRepo.saveRegistrationCallCount, 1);
      provider.dispose();
    });

    test('login shows error when initRegistration returns null', () async {
      authRepo.setLoginResult({
        'uid': 'test-uid',
        'email': 'admin@example.com',
        'admin_email': 'admin@example.com',
      });
      authRepo.setInitResult(null);

      final provider = RegistrationProvider(authRepo, deviceRepo);
      await provider.login('IASB-4208', 'test-pass');

      expect(provider.step, isNot(RegistrationStep.completed));
      expect(provider.errorMessage, isNotNull);
      provider.dispose();
    });

    test('login falls back to OTP when no local registration exists', () async {
      if (_testIsar == null) return;

      authRepo.setLoginResult({
        'uid': 'test-uid',
        'email': 'admin@example.com',
        'admin_email': 'admin@example.com',
      });
      authRepo.setInitResult({
        'status': 'already_registered',
        'smart_board_id': 'IASB-4208',
        'room_id': 'R101',
        'room_name': 'Hall 1',
        'building': 'Main',
        'department': 'CS',
      });

      deviceRepo.setRegistration(null);

      final provider = RegistrationProvider(authRepo, deviceRepo);
      await provider.login('IASB-4208', 'test-pass');

      expect(provider.step, RegistrationStep.otpSent);
      provider.dispose();
    });

    test('already_registered saves profile with correct fields', () async {
      if (_testIsar == null) return;

      authRepo.setLoginResult({
        'uid': 'test-uid',
        'email': 'admin@example.com',
        'admin_email': 'admin@example.com',
      });
      authRepo.setInitResult({
        'status': 'already_registered',
        'smart_board_id': 'IASB-4208',
        'room_id': 'R101',
        'room_name': 'Hall 1',
        'building': 'Main',
        'department': 'CS',
      });

      final reg = DeviceRegistration()
        ..smartBoardId = 'IASB-4208'
        ..hardwareId = 'HW-TEST-001'
        ..roomName = 'Hall 1'
        ..building = 'Main'
        ..department = 'CS'
        ..capacity = 60
        ..registrationDate = DateTime.now();
      deviceRepo.setRegistration(reg);

      final provider = RegistrationProvider(authRepo, deviceRepo);
      await provider.login('IASB-4208', 'test-pass');

      expect(authRepo.savedProfile, isNotNull);
      expect(authRepo.savedProfile!['smart_board_id'], 'IASB-4208');
      expect(authRepo.savedProfile!['room_id'], 'R101');
      expect(authRepo.savedProfile!['room_name'], 'Hall 1');
      provider.dispose();
    });
  });

  group('RegistrationProvider — error states', () {
    test('login returns error when loginResult is null', () async {
      authRepo.setLoginResult(null);
      authRepo.setInitResult(null);

      final provider = RegistrationProvider(authRepo, deviceRepo);
      await provider.login('IASB-4208', 'wrong-id');

      expect(provider.errorMessage, isNotNull);
      expect(provider.step, isNot(RegistrationStep.completed));
      provider.dispose();
    });
  });
}
