import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../core/utils/logger.dart';
import '../../services/session_manager.dart';
import '../../services/hardware_fingerprint_service.dart';
import '../../services/rate_limiter.dart';
import '../../services/secure_storage_service.dart';
import '../../services/startup_service.dart';

enum RegistrationStep { idle, otpSent, verifying, completed, error }

class RegistrationProvider extends ChangeNotifier {
  final IAuthRepository _authRepository;
  final IDeviceRepository _deviceRepository;

  RegistrationProvider(this._authRepository, this._deviceRepository) {
    _loadPersistedToken();
  }

  RegistrationStep _step = RegistrationStep.idle;
  RegistrationStep get step => _step;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _verificationToken;
  String? _adminEmail;
  String? get adminEmail => _adminEmail;

  Timer? _otpTimer;
  int _otpSecondsRemaining = 0;
  int get otpSecondsRemaining => _otpSecondsRemaining;

  String get formattedOtpTime {
    final minutes = (_otpSecondsRemaining / 60).floor();
    final seconds = _otpSecondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPersistedToken() async {
    _verificationToken = await SecureStorageService.getRegistrationToken();
    if (_verificationToken != null) {
      // LOGIC-4 FIX: Advance to the OTP step so the UI shows the PIN entry
      // form, not the login form. The user completed OTP verification before
      // the app crashed/closed — resume exactly where they left off.
      _step = RegistrationStep.otpSent;
      Log.i('[RegistrationProvider] Restored token. Resuming at OTP (hardware binding) step.');
      notifyListeners();
    }
  }

  void _startOtpTimer() {
    _otpTimer?.cancel();
    _otpSecondsRemaining = 600; // 10 minutes
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpSecondsRemaining > 0) {
        _otpSecondsRemaining--;
        notifyListeners();
      } else {
        _otpTimer?.cancel();
        _step = RegistrationStep.idle;
        _errorMessage = 'OTP EXPIRED: Please authenticate again.';
        SecureStorageService.clearRegistrationToken();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    super.dispose();
  }

  Future<void> login(String boardId, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _authRepository.login(boardId, password);
      if (data != null) {
        _adminEmail = data['admin_email'];
        final bool isRegistered = data['is_registered'] ?? false;
        
        if (isRegistered) {
          if (data['profile'] != null) {
            await _authRepository.saveRegistration(data['profile'], SessionManager.isar);
          }
          _step = RegistrationStep.completed;
          Log.i('[RegistrationProvider] Login successful. Device is already registered.');
        } else {
          // Trigger OTP Initiation for the newly logged-in board
          final initResult = await _authRepository.initiateRegistration(boardId, password);
          if (initResult != null) {
            _step = RegistrationStep.otpSent;
            _startOtpTimer();
            Log.i('[RegistrationProvider] Login successful. OTP sent to $_adminEmail');
          } else {
            _errorMessage = 'Failed to initiate registration OTP. Please contact IT.';
          }
        }
      } else {
        _errorMessage = 'Invalid Board ID or Password.';
      }
    } on FirebaseAuthException catch (e) {
      // ... same error handling ...
      _errorMessage = _getFirebaseAuthErrorMessage(e);
      Log.e('[RegistrationProvider] Auth Error: ${e.code}');
    } catch (e) {
      _errorMessage = 'Connection error. Please check your internet and try again.';
      Log.e('[RegistrationProvider] Unexpected Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> verifyOtp(String boardId, String otp) async {
    final rateKey = 'reg_otp_$boardId';
    if (!RateLimiter.isAllowed(rateKey)) {
      final delay = RateLimiter.getDelay(rateKey);
      _errorMessage = 'SECURITY LOCK: Too many attempts. Please wait ${delay.inSeconds}s';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 3 (A): Verify OTP to get Verification Token
      final verifyResult = await _authRepository.verifyOtp(boardId, otp);
      
      if (verifyResult != null && verifyResult['verification_token'] != null) {
        RateLimiter.reset(rateKey);
        _verificationToken = verifyResult['verification_token'];
        
        // Persist token for L-1 recovery
        await SecureStorageService.storeRegistrationToken(_verificationToken!);

        final hardwareId = await HardwareFingerprintService.getDeviceId();

        // Step 3 (B): Use token to bind hardware
        final registrationResult = await _authRepository.completeRegistration(
          boardId, 
          hardwareId, 
          _verificationToken!
        );
        
        if (registrationResult != null) {
          _otpTimer?.cancel();
          final profile = Map<String, dynamic>.from(registrationResult);
          profile['room_id'] = registrationResult['classroom_id'];
          
          await _authRepository.saveRegistration(profile, SessionManager.isar);
          await SecureStorageService.clearRegistrationToken();
          
          _step = RegistrationStep.completed;
          
          // v6.4: Automatically register for Windows Startup on first success
          await StartupService.register();
          
          Log.i('[RegistrationProvider] Hardware bound successfully to $boardId');
        } else {
          _errorMessage = 'Hardware binding failed. Please contact IT.';
        }
      } else {
        RateLimiter.recordAttempt(rateKey);
        _errorMessage = 'Invalid OTP. Please check the code sent to your IT admin.';
      }
    } catch (e) {
      _errorMessage = 'Verification failed. Please check your connection.';
      Log.e('[RegistrationProvider] Verify Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
      return 'DEVICE NOT PROVISIONED\nThis SmartBoard ID is not recognized. Please contact IT Support.';
    } else if (e.code == 'wrong-password') {
      return 'Invalid System Password. Please try again.';
    } else if (e.code == 'user-disabled') {
      return 'SUSPENDED: This SmartBoard has been disabled by an administrator.';
    } else if (e.code == 'too-many-requests') {
      return 'SECURITY LOCK: Too many failed attempts. Please try again later.';
    }
    return 'AUTHENTICATION ERROR: ${e.message}';
  }

  void reset() {
    _otpTimer?.cancel();
    _step = RegistrationStep.idle;
    _errorMessage = null;
    _isLoading = false;
    SecureStorageService.clearRegistrationToken();
    notifyListeners();
  }
}
