import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/firebase_rest_auth.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';

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
      if (idToken == null) {
        Log.e(
            '[AuthRepository] initiateRegistration: no ID token — login() did not complete.');
        return null;
      }

      final response = await apiClient.dio.post(
        '/api/v1/device/register/login',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
        // No body — server identifies the board from the ID token.
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status >= 500) {
        // 5xx: infrastructure error (e.g. Cloudflare 502). The origin server
        // most likely processed the request and sent the OTP before the
        // response was lost. Re-throw so the provider can show the OTP
        // entry screen.
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

  // ─── Registration step 3: hardware bind + custom-token sign-in ─────────

  @override
  Future<Map<String, dynamic>?> completeRegistration(
    String boardId,
    String hardwareId,
    String verificationToken,
  ) async {
    try {
      // Collect hardware metadata while we fetch the ID token in parallel.
      final results = await Future.wait([
        HardwareFingerprintService.getHardwareMetadata(),
        FirebaseRestAuth.getIdToken(),
      ]);

      final metadata = results[0] as Map<String, dynamic>;
      final idToken = results[1] as String?;

      final response = await apiClient.dio.post(
        '/api/v1/device/register/complete',
        options: Options(
          headers: idToken != null
              ? {'Authorization': 'Bearer $idToken'}
              : null,
        ),
        data: {
          'smart_board_id': boardId,
          'hardware_id': hardwareId,
          'verification_token': verificationToken,
          'metadata': metadata,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // Exchange the server-issued custom token (carries the role:smartboard
        // claim) for a normal ID + refresh token pair via REST. This replaces
        // the original `_auth.signInWithCustomToken()` plugin call.
        //
        // The custom token may occasionally come back stale from server-side
        // caching of a prior 502'd attempt. In that case we keep the existing
        // email/password session (already persisted by the login() step) so
        // the device can still operate; the missing role claim is surfaced
        // to the server on the next call and IT can re-issue manually.
        final customToken = data['custom_token']?.toString();
        if (customToken != null && customToken.isNotEmpty) {
          try {
            await FirebaseRestAuth.signInWithCustomToken(customToken);
            Log.i(
                '[AuthRepository] signInWithCustomToken (REST) succeeded — role:smartboard claims active.');
          } catch (tokenError) {
            Log.w(
                '[AuthRepository] signInWithCustomToken (REST) failed ($tokenError). '
                'Email/password session retained as fallback.');
          }
        } else {
          Log.w(
              '[AuthRepository] Server did not return a custom_token — using email/password session.');
        }

        // Store hardwareId as the long-lived API key for heartbeat / telemetry
        // identification. SecureStorage is DPAPI-encrypted on Windows.
        await SecureStorageService.storeApiKey(hardwareId);

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
      ..registrationDate = DateTime.now();

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
