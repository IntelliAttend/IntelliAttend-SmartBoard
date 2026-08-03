import 'dart:async';

import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/firebase_rest_auth.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../core/auth/token_manager.dart';
import '../../models/isar_schemas.dart';
import '../../services/time_sync_service.dart';

/// Thrown when a server call fails with a specific, user-facing reason.
class ServerAuthException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;

  ServerAuthException({
    required this.statusCode,
    required this.message,
    this.errorCode,
  });

  @override
  String toString() => 'ServerAuthException($statusCode: $message)';
}

abstract class IAuthRepository {
  Future<Map<String, dynamic>?> login(String boardId, String password);
  Future<Map<String, dynamic>?> initiateRegistration(
      String boardId, String password);
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp);
  Future<Map<String, dynamic>?> completeRegistration(
      String boardId, String hardwareId, String verificationToken,
      {Map<String, dynamic>? metadata});
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar,
      {String? hardwareId});
  Future<void> logout();
}

/// Auth repository — PURE-REST. No `firebase_auth` plugin, no
/// plugin. All Firebase touchpoints go through
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
    final normalizedBoardId = boardId.trim().toUpperCase();
    try {
      Log.i('[AuthRepository] Attempting REST login for Board: $normalizedBoardId');

      final email = AppConfig.boardIdToEmail(normalizedBoardId);

      final authData =
          await FirebaseRestAuth.signInWithPassword(email, password);
      final uid = authData['localId']?.toString();
      final returnedEmail = authData['email']?.toString();

      if (uid == null) return null;

      await SecureStorageService.storeBoardCredentials(email, password);

      return {
        'uid': uid,
        'email': returnedEmail,
        'admin_email': returnedEmail ?? 'IT Administrator',
        'profile': null,
      };
    } on FirebaseRestAuthException catch (e) {
      Log.e('[AuthRepository] REST login failed: ${e.code}');
      rethrow;
    } on TimeoutException {
      Log.e('[AuthRepository] Login timed out');
      throw ServerAuthException(
        statusCode: 0,
        message: 'Connection timed out. Check your network and try again.',
        errorCode: 'TIMEOUT',
      );
    } catch (e) {
      Log.e('[AuthRepository] Unexpected login error: $e');
      throw ServerAuthException(
        statusCode: 0,
        message: 'Failed to connect to authentication server. Check your internet.',
        errorCode: 'NETWORK_ERROR',
      );
    }
  }

  // ─── Registration step 1: initiate (send OTP) ───────────────────────────

  @override
  Future<Map<String, dynamic>?> initiateRegistration(
      String boardId, String password) async {
    final normalizedBoardId = boardId.trim().toUpperCase();
    try {
      final response = await apiClient.dio.post(
        '/api/v1/device/register/login',
        data: {
          'smart_board_id': normalizedBoardId,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final detail = _extractServerDetail(e);

      if (status == 401) {
        throw ServerAuthException(
          statusCode: 401,
          message: detail ?? 'Authentication failed. The server rejected your credentials.',
          errorCode: 'AUTH_FAILED',
        );
      }
      if (status == 403) {
        throw ServerAuthException(
          statusCode: 403,
          message: detail ?? 'Access denied. This board may be suspended.',
          errorCode: 'ACCESS_DENIED',
        );
      }
      if (status >= 500) {
        throw ServerAuthException(
          statusCode: status,
          message: 'Server is temporarily unavailable. Please try again shortly.',
          errorCode: 'SERVER_ERROR',
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw ServerAuthException(
          statusCode: 0,
          message: 'Connection timed out. Check your network and try again.',
          errorCode: 'TIMEOUT',
        );
      }
      if (e.type == DioExceptionType.connectionError) {
        throw ServerAuthException(
          statusCode: 0,
          message: 'Cannot reach the server. Check your internet connection.',
          errorCode: 'NO_CONNECTION',
        );
      }
      throw ServerAuthException(
        statusCode: status,
        message: detail ?? 'Registration failed (HTTP $status). Please try again.',
        errorCode: 'HTTP_$status',
      );
    } catch (e) {
      if (e is ServerAuthException) rethrow;
      Log.e('[AuthRepository] initiateRegistration failed: $e');
      throw ServerAuthException(
        statusCode: 0,
        message: 'An unexpected error occurred. Please try again.',
        errorCode: 'UNKNOWN',
      );
    }
  }

  String? _extractServerDetail(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String) return detail;
        if (detail is Map) return detail['message']?.toString();
        return data['message']?.toString();
      }
    } catch (_) {}
    return null;
  }

  // ─── Registration step 2: verify OTP ─────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async {
    final normalizedBoardId = boardId.trim().toUpperCase();
    try {
      final response = await apiClient.dio.post(
        '/api/v1/device/register/verify',
        data: {
          'smart_board_id': normalizedBoardId,
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
    String verificationToken, {
    Map<String, dynamic>? metadata,
  }) async {
    final normalizedBoardId = boardId.trim().toUpperCase();
    try {
      final response = await apiClient.dio.post(
        '/api/v1/device/register/complete',
        data: {
          'smart_board_id': normalizedBoardId,
          'hardware_id': hardwareId,
          'verification_token': verificationToken,
          if (metadata != null) 'metadata': metadata,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        final customToken = data['custom_token']?.toString();
        if (customToken != null && customToken.isNotEmpty) {
          try {
            await FirebaseRestAuth.signInWithCustomToken(customToken);
            Log.i('[AuthRepository] Custom-token exchange successful — session bound to hardware.');
          } catch (e) {
            Log.w('[AuthRepository] Custom-token exchange failed (non-fatal): $e');
          }
        }

        return data;
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final detail = _extractServerDetail(e);

      if (status == 401) {
        throw ServerAuthException(
          statusCode: 401,
          message: detail ?? 'Verification token expired or invalid. Please re-login.',
          errorCode: 'TOKEN_INVALID',
        );
      }
      if (status == 403) {
        throw ServerAuthException(
          statusCode: 403,
          message: detail ?? 'Board registration denied. Contact administration.',
          errorCode: 'REGISTRATION_DENIED',
        );
      }
      if (status >= 500) {
        throw ServerAuthException(
          statusCode: status,
          message: 'Server error during hardware binding. The app will retry on next launch.',
          errorCode: 'SERVER_ERROR',
        );
      }
      throw ServerAuthException(
        statusCode: status,
        message: detail ?? 'Hardware binding failed (HTTP $status).',
        errorCode: 'HTTP_$status',
      );
    } catch (e) {
      if (e is ServerAuthException) rethrow;
      Log.e('[AuthRepository] completeRegistration failed: $e');
      throw ServerAuthException(
        statusCode: 0,
        message: 'Hardware binding failed due to a network error.',
        errorCode: 'NETWORK_ERROR',
      );
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

  // ─── Deregister (factory reset) ────────────────────────────────────────

  /// Clears all local registration data: Isar records, Firebase tokens,
  /// and secure storage. The app will return to the registration screen
  /// on next launch.
  Future<void> deregister(Isar isar) async {
    try {
      // Clear Isar device registration + hydration data
      await isar.writeTxn(() async {
        await isar.deviceRegistrations.clear();
        await isar.hydrationProfiles.clear();
        await isar.timetableEntrys.clear();
        await isar.storedNotifications.clear();
        await isar.activeSessions.clear();
        await isar.queuedScans.clear();
        await isar.completedSessions.clear();
        await isar.hydrationRosters.clear();
      });

      // Clear Firebase tokens + secure storage
      await FirebaseRestAuth.signOut();
      await SecureStorageService.clearAll();

      // Reset TokenManager in-memory cache so stale tokens from the
      // previous session are never reused after re-login.
      TokenManager().invalidateCache();

      Log.i('[AuthRepository] Device deregistered — all local data cleared.');
    } catch (e) {
      Log.e('[AuthRepository] Deregister failed: $e');
      rethrow;
    }
  }
}
