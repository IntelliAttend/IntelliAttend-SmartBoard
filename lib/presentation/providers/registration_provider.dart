import 'package:flutter/material.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../core/utils/logger.dart';

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
          _step = RegistrationStep.completed;
        } else {
          _step = RegistrationStep.otpSent;
        }
      } else {
        _errorMessage = 'Invalid Board ID or Password.';
      }
    } catch (e) {
      _errorMessage = 'Connection error. Please try again.';
      Log.e('[RegistrationProvider] Error: $e');
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
      final data = await _authRepository.verifyOtp(boardId, otp);
      if (data != null && data['verification_token'] != null) {
        _verificationToken = data['verification_token'];
        
        // Auto-complete binding
        final bound = await _authRepository.completeBinding(_verificationToken!);
        if (bound) {
          _step = RegistrationStep.completed;
        } else {
          _errorMessage = 'Hardware binding failed. Please retry.';
        }
      } else {
        _errorMessage = 'Invalid OTP. Please try again.';
      }
    } catch (e) {
      _errorMessage = 'Verification failed. Please try again.';
      Log.e('[RegistrationProvider] Error: $e');
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
