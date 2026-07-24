// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../core/security/firebase_rest_auth.dart';
import '../../core/utils/logger.dart';
import '../../services/session_manager.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/startup_service.dart';
import '../../main.dart' show startBackgroundProtocols;

enum RegistrationStep { idle, completed }
enum HydrationState { pending, hydrating, completed, failed }

class RegistrationProvider extends ChangeNotifier {
  final IAuthRepository _authRepository;
  final IDeviceRepository _deviceRepository;

  RegistrationProvider(this._authRepository, this._deviceRepository) {
    _attemptAutoRecovery();
  }

  RegistrationStep _step = RegistrationStep.idle;
  RegistrationStep get step => _step;

  HydrationState _hydrationState = HydrationState.pending;
  HydrationState get hydrationState => _hydrationState;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _verificationToken;
  String? _adminEmail;
  String? get adminEmail => _adminEmail;

  /// Await hydration from the server. This must complete BEFORE
  /// setting _step = completed so that the UI has data in Isar
  /// when it navigates to IdleScreen.
  Future<void> _hydrateAndWait() async {
    _hydrationState = HydrationState.hydrating;
    notifyListeners();
    try {
      await _deviceRepository.hydrateFromServer();
      _hydrationState = HydrationState.completed;
    } catch (e) {
      Log.w('[RegistrationProvider] Post-login hydration failed: $e');
      _hydrationState = HydrationState.failed;
    }
  }

  Future<void> _attemptAutoRecovery() async {
    final token = await SecureStorageService.getRegistrationToken();
    final boardId = await SecureStorageService.read('reg_board_id');

    if (token == null || boardId == null) return;

    Log.i('[RegistrationProvider] Persisted registration state found — '
        'attempting auto-recovery (board=$boardId).');
    _isLoading = true;
    notifyListeners();

    try {
      final hardwareId = await HardwareFingerprintService.getDeviceId();
      final metadata = await HardwareFingerprintService.getHardwareMetadata();
      final result = await _authRepository.completeRegistration(
          boardId, hardwareId, token,
          metadata: metadata);

      if (result != null) {
        final profile = Map<String, dynamic>.from(result);
        profile['room_id'] = profile['classroom_id'] ?? profile['room_id'];

        await _authRepository.saveRegistration(
            profile, SessionManager.isar,
            hardwareId: hardwareId);

        await SecureStorageService.clearRegistrationToken();
        await SecureStorageService.delete('reg_board_id');

        await _hydrateAndWait();
        _step = RegistrationStep.completed;
        unawaited(StartupService.register());
        unawaited(startBackgroundProtocols());
        Log.i('[RegistrationProvider] Auto-recovery succeeded for $boardId.');
        return;
      }
    } catch (e) {
      Log.w('[RegistrationProvider] Auto-recovery failed: $e');
    }

    await SecureStorageService.clearRegistrationToken();
    await SecureStorageService.delete('reg_board_id');
    _errorMessage = 'Previous registration attempt failed. Please re-enter credentials.';
    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String boardId, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _authRepository.login(boardId, password);
      if (data != null) {
        _adminEmail = data['admin_email'];

        try {
          final initResult =
              await _authRepository.initiateRegistration(boardId, password);

          if (initResult != null) {
            Log.i('[RegistrationProvider] initiateRegistration: $initResult');

            if (initResult['is_registered'] == true ||
                initResult['status'] == 'already_registered') {
              Log.i('[RegistrationProvider] Board already registered. '
                  'Binding hardware to obtain custom_token + profile.');

              final hardwareId = await HardwareFingerprintService.getDeviceId();
              final metadata =
                  await HardwareFingerprintService.getHardwareMetadata();

              Map<String, dynamic>? completeResult;
              try {
                completeResult = await _authRepository.completeRegistration(
                    boardId, hardwareId, '',
                    metadata: metadata);
              } catch (e) {
                Log.w('[RegistrationProvider] completeRegistration for existing '
                    'board failed (non-fatal): $e');
              }

              final profile = <String, dynamic>{
                ...initResult,
                if (completeResult != null) ...completeResult,
              };
              profile['smart_board_id'] =
                  initResult['smart_board_id'] ?? boardId;
              profile['room_id'] =
                  profile['room_id'] ?? profile['classroom_id'];

              await _authRepository.saveRegistration(
                profile,
                SessionManager.isar,
                hardwareId: hardwareId,
              );
              Log.i('[RegistrationProvider] Registration saved for existing board.');

              await _hydrateAndWait();
              _step = RegistrationStep.completed;
              unawaited(StartupService.register());
              unawaited(startBackgroundProtocols());
              Log.i('[RegistrationProvider] Board already registered. '
                  'Hardware bound. Entering Idle state.');
              return;
            }

            final verificationToken =
                initResult['verification_token'] as String?;

            if (verificationToken != null && verificationToken.isNotEmpty) {
              Log.i('[RegistrationProvider] New server flow: verification_token '
                  'received — completing registration without OTP.');

              _verificationToken = verificationToken;
              await SecureStorageService.storeRegistrationToken(verificationToken);
              await SecureStorageService.write('reg_board_id', boardId);

              final hardwareId =
                  await HardwareFingerprintService.getDeviceId();
              final metadata =
                  await HardwareFingerprintService.getHardwareMetadata();

              final completeResult =
                  await _authRepository.completeRegistration(
                      boardId, hardwareId, verificationToken,
                      metadata: metadata);

              if (completeResult == null) {
                _errorMessage =
                    'Hardware binding failed. The app will retry on next launch.';
                Log.e('[RegistrationProvider] completeRegistration returned null');
                return;
              }

              final profile = <String, dynamic>{
                ...initResult,
                ...completeResult,
              };
              profile['smart_board_id'] =
                  initResult['smart_board_id'] ?? boardId;
              profile['room_id'] =
                  profile['room_id'] ?? profile['classroom_id'];

              await _authRepository.saveRegistration(
                profile,
                SessionManager.isar,
                hardwareId: hardwareId,
              );

              await SecureStorageService.clearRegistrationToken();
              await SecureStorageService.delete('reg_board_id');

              await _hydrateAndWait();
              _step = RegistrationStep.completed;
              unawaited(StartupService.register());
              unawaited(startBackgroundProtocols());
              Log.i('[RegistrationProvider] Board registered successfully (no OTP).');
              return;
            }

            _errorMessage =
                'Server response missing verification data. Please contact IT.';
          } else {
            _errorMessage =
                'Failed to initiate registration. Please contact IT.';
          }
        } on DioException catch (e) {
          final status = e.response?.statusCode ?? 0;
          if (status >= 500) {
            _errorMessage =
                'Server temporarily unavailable. Please try again in a moment.';
          } else {
            _errorMessage =
                'Failed to initiate registration. Please contact IT.';
          }
          Log.e('[RegistrationProvider] initiateRegistration DioException ($status): $e');
        }
      } else {
        _errorMessage = 'Invalid Board ID or Password.';
      }
    } on FirebaseRestAuthException catch (e) {
      _errorMessage = _restAuthErrorMessage(e);
      Log.e('[RegistrationProvider] Auth Error: ${e.code}');
    } catch (e) {
      _errorMessage =
          'Connection error. Please check your internet and try again.';
      Log.e('[RegistrationProvider] Unexpected Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _restAuthErrorMessage(FirebaseRestAuthException e) {
    final code = e.code;
    if (code == 'EMAIL_NOT_FOUND' ||
        code == 'INVALID_LOGIN_CREDENTIALS' ||
        code == 'INVALID_EMAIL') {
      return 'DEVICE NOT PROVISIONED\nThis SmartBoard ID is not recognized. Please contact IT Support.';
    }
    if (code == 'INVALID_PASSWORD' || code == 'MISSING_PASSWORD') {
      return 'Invalid System Password. Please try again.';
    }
    if (code == 'USER_DISABLED') {
      return 'SUSPENDED: This SmartBoard has been disabled by an administrator.';
    }
    if (code.startsWith('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'SECURITY LOCK: Too many failed attempts. Please try again later.';
    }
    return 'AUTHENTICATION ERROR: $code';
  }

  void reset() {
    _step = RegistrationStep.idle;
    _hydrationState = HydrationState.pending;
    _errorMessage = null;
    _isLoading = false;
    SecureStorageService.clearRegistrationToken();
    notifyListeners();
  }
}
