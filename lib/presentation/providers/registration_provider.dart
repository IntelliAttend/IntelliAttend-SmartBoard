import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../core/utils/logger.dart';
import '../../services/session_manager.dart';
import '../../services/hardware_fingerprint_service.dart';

enum RegistrationStep { idle, otpSent, verifying, completed, error }

class RegistrationProvider extends ChangeNotifier {
  final IAuthRepository _authRepository;
  final IDeviceRepository _deviceRepository;

  RegistrationProvider(this._authRepository, this._deviceRepository);

  RegistrationStep _step = RegistrationStep.idle;
  RegistrationStep get step => _step;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _verificationToken;
  String? _adminEmail;
  String? get adminEmail => _adminEmail;

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
            Log.i('[RegistrationProvider] Login successful. OTP sent to $_adminEmail');
          } else {
            _errorMessage = 'Failed to initiate registration OTP. Please contact IT.';
          }
        }
      } else {
        _errorMessage = 'Invalid Board ID or Password.';
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        _errorMessage = 'DEVICE NOT PROVISIONED\nThis SmartBoard ID is not recognized or has been unassigned. Please contact IT Support.';
      } else if (e.code == 'wrong-password') {
        _errorMessage = 'Invalid System Password. Please try again.';
      } else if (e.code == 'user-disabled') {
        _errorMessage = 'SUSPENDED: This SmartBoard has been disabled by an administrator.';
      } else if (e.code == 'too-many-requests') {
        _errorMessage = 'SECURITY LOCK: Too many failed attempts. Please try again later.';
      } else {
        _errorMessage = 'AUTHENTICATION ERROR: ${e.message}';
      }
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
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 3 (A): Verify OTP to get Verification Token
      final verifyResult = await _authRepository.verifyOtp(boardId, otp);
      
      if (verifyResult != null && verifyResult['verification_token'] != null) {
        final verificationToken = verifyResult['verification_token'];
        final hardwareId = await HardwareFingerprintService.getDeviceId();

        // Step 3 (B): Use token to bind hardware
        final registrationResult = await _authRepository.completeRegistration(
          boardId, 
          hardwareId, 
          verificationToken
        );
        
        if (registrationResult != null) {
          // Map backend fields to frontend profile expectations if necessary
          final profile = Map<String, dynamic>.from(registrationResult);
          profile['room_id'] = registrationResult['classroom_id']; // Alias for saveRegistration
          
          await _authRepository.saveRegistration(profile, SessionManager.isar);
          
          _step = RegistrationStep.completed;
          Log.i('[RegistrationProvider] Hardware binding successful and cached.');
        } else {
          _errorMessage = 'Hardware binding failed. Please contact IT.';
        }
      } else {
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

  void reset() {
    _step = RegistrationStep.idle;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
