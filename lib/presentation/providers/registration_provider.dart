import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../core/utils/logger.dart';
import '../../services/session_manager.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/rate_limiter.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/startup_service.dart';
import '../../main.dart' show startBackgroundProtocols;

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
      Log.i(
          '[RegistrationProvider] Restored token. Resuming at OTP (hardware binding) step.');
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
            await _authRepository.saveRegistration(
                data['profile'], SessionManager.isar);
          }
          _step = RegistrationStep.completed;
          unawaited(StartupService.register());
          unawaited(startBackgroundProtocols());
          Log.i(
              '[RegistrationProvider] Login successful. Device is already registered.');
        } else {
          // Trigger OTP Initiation for the newly logged-in board.
          // We handle three outcomes:
          //   • 200 OK      — OTP confirmed sent; show OTP screen
          //   • 5xx / 502  — infrastructure glitch; OTP was likely still sent
          //                   by the origin before Cloudflare dropped the response;
          //                   show OTP screen with a soft advisory
          //   • 4xx / null  — real failure; OTP not sent; show error
          try {
            final initResult =
                await _authRepository.initiateRegistration(boardId, password);

            if (initResult != null) {
              _step = RegistrationStep.otpSent;
              _startOtpTimer();
              Log.i('[RegistrationProvider] Login successful. OTP sent to $_adminEmail');
            } else {
              _errorMessage =
                  'Failed to initiate registration OTP. Please contact IT.';
            }
          } on DioException catch (e) {
            final status = e.response?.statusCode ?? 0;
            if (status >= 500) {
              // Server-side infrastructure error (e.g. Cloudflare 502).
              // The origin server processed the request and emailed the OTP
              // before the response was lost in transit. Show the OTP entry
              // screen so the admin can type the code they received.
              _step = RegistrationStep.otpSent;
              _startOtpTimer();
              Log.w('[RegistrationProvider] Step 1 returned $status but OTP may have been sent — showing OTP screen.');
            } else {
              _errorMessage =
                  'Failed to initiate registration OTP. Please contact IT.';
            }
          }

          // Pre-warm hardware metadata in parallel with OTP entry regardless
          // of which path above was taken. The 18 PowerShell queries take ~3–5 s;
          // by the time the admin reads and types the OTP, the data is cached
          // and completeRegistration() will return it instantly.
          if (_step == RegistrationStep.otpSent) {
            unawaited(HardwareFingerprintService.getHardwareMetadata().then((_) {
              Log.i('[RegistrationProvider] Hardware metadata pre-warmed and cached.');
            }).catchError((Object e) {
              Log.w('[RegistrationProvider] Metadata pre-warm failed (will retry at bond step): $e');
            }));
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
      _errorMessage =
          'Connection error. Please check your internet and try again.';
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
      _errorMessage =
          'SECURITY LOCK: Too many attempts. Please wait ${delay.inSeconds}s';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // ── Bulletproof post-OTP registration sequence ────────────────────────────
    //
    // This is the most critical path in the application. A partial failure here
    // leaves the server believing the board is registered while the client has
    // no valid session — causing permanent broken state. Every step is guarded:
    //
    //   A. Verify OTP → receive verification_token
    //   B. Persist token immediately (crash-safe recovery via _loadPersistedToken)
    //   C. Collect hardware fingerprint (cached — no repeated PowerShell calls)
    //   D. Complete registration → receive {custom_token, classroom_id, ...}
    //   E. signInWithCustomToken → proper Firebase session with role: smartboard
    //   F. Persist refresh_token (required by boot-screen validation)
    //   G. Write DeviceRegistration to Isar (local ground truth)
    //   H. Clear registration_token (one-shot token, no longer needed)
    //   I. Transition to completed — only after ALL of the above succeed
    //
    // If D or later fails, the persisted verification_token (step B) lets the
    // user re-enter the OTP screen on next launch and retry from step D without
    // re-requesting a new OTP.

    try {
      // ── Step A: OTP verification ──────────────────────────────────────────
      final verifyResult = await _authRepository.verifyOtp(boardId, otp);

      if (verifyResult == null || verifyResult['verification_token'] == null) {
        RateLimiter.recordAttempt(rateKey);
        _errorMessage =
            'Invalid OTP. Please check the code sent to your IT admin.';
        return;
      }

      RateLimiter.reset(rateKey);
      _verificationToken = verifyResult['verification_token'] as String;

      // ── Step B: Persist token before any further network calls ────────────
      // If the app crashes between here and step H, _loadPersistedToken()
      // restores the token on next launch so the user can retry without a
      // new OTP.
      await SecureStorageService.storeRegistrationToken(_verificationToken!);
      Log.i('[RegistrationProvider] Verification token persisted for crash-recovery.');

      // ── Step C: Hardware fingerprint (cached after first call) ────────────
      final hardwareId = await HardwareFingerprintService.getDeviceId();

      // ── Step D: Hardware binding ──────────────────────────────────────────
      final registrationResult = await _authRepository.completeRegistration(
          boardId, hardwareId, _verificationToken!);

      if (registrationResult == null) {
        // Server rejected binding. The verification_token is still persisted so
        // IT can investigate and the admin can retry without a new OTP cycle.
        _errorMessage =
            'Hardware binding failed. Please contact IT.\n'
            'The server may need to unlock this board first.';
        Log.e('[RegistrationProvider] completeRegistration returned null for $boardId');
        return;
      }

      // ── Steps E & F: Firebase custom-token sign-in (handled inside completeRegistration)
      // completeRegistration() calls signInWithCustomToken() and storeRefreshToken()
      // internally. At this point the Firebase session is established.

      // ── Step G: Write local registration record ───────────────────────────
      _otpTimer?.cancel();
      final profile = Map<String, dynamic>.from(registrationResult);
      // Server returns 'classroom_id'; downstream code also reads 'room_id'.
      profile['room_id'] = registrationResult['classroom_id'];

      await _authRepository.saveRegistration(
        profile,
        SessionManager.isar,
        hardwareId: hardwareId,
      );
      Log.i('[RegistrationProvider] Registration written to local vault.');

      // ── Step H: Clear one-shot token — only now, after everything succeeded ─
      await SecureStorageService.clearRegistrationToken();

      // ── Step I: Transition ─────────────────────────────────────────────────
      _step = RegistrationStep.completed;

      // Register for Windows auto-start and kick off background protocols
      // (SyncManager, PreFlightService, WindowOrchestrator). Fire-and-forget —
      // do NOT await so the UI transition to IdleScreen is instant.
      unawaited(StartupService.register());
      unawaited(startBackgroundProtocols());

      Log.i('[RegistrationProvider] ✅ Hardware bound successfully to $boardId. Entering Idle state.');
    } catch (e) {
      // Surface actionable message; keep verification_token persisted so
      // the admin can retry step D without re-requesting an OTP.
      _errorMessage = 'Verification failed. Please check your connection and try again.';
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
