import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/firebase_rest_auth.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../services/time_sync_service.dart';

abstract class IAuthRepository {
  Future<Map<String, dynamic>?> login(String boardId, String password);
  Future<Map<String, dynamic>?> initiateRegistration(
      String boardId, String password);
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp);
  Future<Map<String, dynamic>?> completeRegistration(
      String boardId, String hardwareId, String verificationToken);
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar,
      {String? hardwareId});
  Future<void> logout();
}

/// Auth repository — PURE-REST. No `firebase_auth` plugin, no
/// `cloud_firestore` plugin. All Firebase touchpoints go through
/// [FirebaseRestAuth] (Identity Toolkit + Secure Token API only); all
/// registration/profile data goes through the server's REST contract.
///
/// This avoids the Firebase C++ Auth SDK threading bug on Windows that calls
/// `abort()` when its native listeners deliver callbacks on non-platform
/// threads.
class AuthRepository implements IAuthRepository {
  final ApiClient apiClient;

  AuthRepository(this.apiClient);

  // ─── Admin login ─────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> login(String boardId, String password) async {
    try {
      Log.i('[AuthRepository] Attempting REST login for Board: $boardId');

      // SmartBoard ID is mapped to a lowercase email format per the
      // Accountable Device spec.
      final email = AppConfig.boardIdToEmail(boardId);

      final authData =
          await FirebaseRestAuth.signInWithPassword(email, password);
      final uid = authData['localId']?.toString();
      final returnedEmail = authData['email']?.toString();

      if (uid == null) return null;

      // Persist board credentials for Firebase plugin authentication on boot.
      // This enables .snapshots() streams (billed only on data changes).
      await SecureStorageService.storeBoardCredentials(email, password);

      // We no longer read the `smart_boards` Firestore doc directly. Whether
      // the device is already registered is now resolved server-side during
      // `/api/v1/device/register/login` — that response contains the same
      // profile fields the Firestore doc used to carry. RegistrationProvider
      // calls initiateRegistration() right after login() and handles the
      // "already registered" branch from the server response.
      return {
        'uid': uid,
        'email': returnedEmail,
        'is_registered': false, // server is the source of truth from here on
        'admin_email': returnedEmail ?? 'IT Administrator',
        'profile': null,
      };
    } on FirebaseRestAuthException catch (e) {
      Log.e('[AuthRepository] REST login failed: ${e.code}');
      rethrow;
    } catch (e) {
      Log.e('[AuthRepository] Unexpected login error: $e');
      return null;
    }
  }

  // ─── Registration step 1: initiate (send OTP) ───────────────────────────

  @override
  Future<Map<String, dynamic>?> initiateRegistration(
      String boardId, String password) async {
    try {
      final idToken = await FirebaseRestAuth.getIdToken();
      
      final response = await apiClient.dio.post(
        '/api/v1/device/register/login',
        options: Options(
          headers: idToken != null ? {'Authorization': 'Bearer $idToken'} : null,
        ),
        data: {
          'smart_board_id': boardId,
        },
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status >= 500) {
        Log.w(
            '[AuthRepository] initiateRegistration got $status — OTP may have been sent. Re-throwing.');
        rethrow;
      }
      Log.e('[AuthRepository] initiateRegistration failed ($status): $e');
      return null;
    } catch (e) {
      Log.e('[AuthRepository] initiateRegistration failed: $e');
      return null;
    }
  }

  // ─── Registration step 2: verify OTP ─────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/device/register/verify',
        data: {
          'smart_board_id': boardId,
          'otp': otp,
        },
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] OTP verification failed: $e');
      return null;
    }
  }

  // ─── Registration step 3: hardware bind + JWT persistence ───────────────

  @override
  Future<Map<String, dynamic>?> completeRegistration(
    String boardId,
    String hardwareId,
    String verificationToken,
  ) async {
    try {
      final idToken = await FirebaseRestAuth.getIdToken();

      final response = await apiClient.dio.post(
        '/api/v1/device/register/complete',
        options: Options(
          headers: idToken != null ? {'Authorization': 'Bearer $idToken'} : null,
        ),
        data: {
          'smart_board_id': boardId,
          'hardware_id': hardwareId,
          'verification_token': verificationToken,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // v5.4 JWT Strategy: The backend now returns access_token and refresh_token
        // directly. We persist these to SecureStorage for use by the AuthInterceptor.
        final accessToken = data['access_token']?.toString();
        final refreshToken = data['refresh_token']?.toString();
        final expiresIn = data['expires_in'] as int? ?? 3600;

        if (accessToken != null && refreshToken != null) {
          final expiryMs = TimeSyncService.timeNow.millisecondsSinceEpoch + (expiresIn * 1000);
          await SecureStorageService.storeAccessToken(accessToken, expiryMs);
          await SecureStorageService.storeRefreshToken(refreshToken);
          
          // Also store hardwareId as the long-lived API key for secondary verification
          await SecureStorageService.storeApiKey(hardwareId);
          
          Log.i('[AuthRepository] Registration complete. v5.4 JWTs persisted.');
        } else {
          Log.w('[AuthRepository] Server did not return tokens — fallback to legacy might be needed.');
        }

        return data;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] completeRegistration failed: $e');
      return null;
    }
  }

  // ─── Local persistence ──────────────────────────────────────────────────

  @override
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar,
      {String? hardwareId}) async {
    final resolvedHardwareId =
        hardwareId ?? await HardwareFingerprintService.getDeviceId();
    final reg = DeviceRegistration()
      ..smartBoardId =
          profile['smart_board_id'] ?? profile['board_id'] ?? 'UNKNOWN'
      ..classroomId =
          profile['room_id'] ?? profile['classroom_id'] ?? 'UNKNOWN'
      ..roomName = profile['room_name'] ?? 'Unknown'
      ..building = profile['building'] ?? 'Unknown'
      ..department = profile['department'] ?? 'Unknown'
      ..capacity = profile['capacity'] ?? 60
      ..hardwareId = resolvedHardwareId
      ..registrationDate = TimeSyncService.timeNow;

    await isar.writeTxn(() async {
      await isar.deviceRegistrations.put(reg);
    });
    Log.i('[AuthRepository] Device registration cached to Isar.');
  }

  // ─── Logout ─────────────────────────────────────────────────────────────

  @override
  Future<void> logout() async {
    await FirebaseRestAuth.signOut();
    await SecureStorageService.clearAll();
    Log.i('[AuthRepository] Logged out (REST tokens cleared).');
  }
}
