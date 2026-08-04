import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../core/rate_limiter.dart';
import '../../services/api_service.dart';
import '../../services/session_state_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/pin_input.dart';
import '../../core/security/secure_storage_service.dart';
import '../../services/session_manager.dart';
import '../../services/time_sync_service.dart';

class IgnitingScreen extends StatefulWidget {
  final String courseName;
  final String facultyName;
  final String roomName;
  final int capacity;
  final String? smartBoardId;

  const IgnitingScreen({
    super.key,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    required this.capacity,
    this.smartBoardId,
  });

  @override
  State<IgnitingScreen> createState() => _IgnitingScreenState();
}

class _IgnitingScreenState extends State<IgnitingScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isKeypadExpanded = true;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmitOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      setState(() => _errorMessage = 'Please enter a valid 4-digit PIN');
      return;
    }

    final rateKey = 'igniting_otp_${widget.smartBoardId ?? 'board'}';
    if (!RateLimiter.isAllowed(rateKey)) {
      setState(() => _errorMessage =
          'Too many attempts. Please wait before trying again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _otpController.clear();
      final result = await ApiService.initiateSession(otp);
      RateLimiter.reset(rateKey);

      final data = result['data'] ?? result;
      final sessionId = data['session_id']?.toString();
      final sessionSecret = data['session_secret']?.toString();
      final accessToken = data['access_token']?.toString();

      if (sessionId == null || sessionSecret == null) {
        setState(() {
          _errorMessage = 'Invalid server response. Please try again.';
          _isLoading = false;
        });
        return;
      }

      final rosterCount = data['roster_count'] is int
          ? data['roster_count']
          : int.tryParse(data['roster_count']?.toString() ?? '0') ?? 0;
      final courseName = data['course_name']?.toString() ?? widget.courseName;
      final facultyName = data['faculty_name']?.toString() ?? widget.facultyName;
      final sectionId = data['section_id']?.toString() ?? '';

      await SessionManager.saveSession(
        sessionId: sessionId,
        rosterCount: rosterCount,
        facultyName: facultyName,
        courseName: courseName,
        sectionId: sectionId,
        endTime: TimeSyncService.timeNow.add(const Duration(hours: 1)),
      );

      await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);

      if (!mounted) return;

      SessionStateService().storeSessionSecrets(
        sessionSecret,
        accessToken,
      );
      SessionStateService().applyState(SessionState(
        sessionId: sessionId,
        state: 'ACTIVE',
        websocketToken: accessToken,
        courseName: courseName,
        facultyName: facultyName,
        sectionId: sectionId,
        roomName: widget.roomName,
        presentCount: 0,
      ));
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.userMessage;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      body: Stack(
        children: [
          Opacity(
            opacity: isDark ? 0.05 : 0.03,
            child: Center(
              child: Image.asset(
                'assets/background.png',
                width: size.width * 0.6,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Center(
            child: GlassContainer(
              width: 420,
              padding: const EdgeInsets.all(40),
              borderRadius: 32,
              color: isDark
                  ? AppColors.surfaceDark.withValues(alpha: 0.9)
                  : Colors.white,
              borderColor: AppColors.primaryTeal.withValues(alpha: 0.3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      color: AppColors.primaryTeal,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'VERIFY SESSION',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 4-digit PIN from your mobile',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.courseName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryTeal,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () {
                      setState(() => _isKeypadExpanded = !_isKeypadExpanded);
                    },
                    child: PinInput(
                      value: _otpController.text,
                      obscureText: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: _buildNumericKeypad(isDark),
                    crossFadeState: _isKeypadExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 400),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSubmitOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_outline, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'VERIFY & START',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad(bool isDark) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++)
          _keypadButton(i.toString(), isDark),
        const SizedBox(),
        _keypadButton('0', isDark),
        _keypadButton('backspace', isDark, isAction: true),
      ],
    );
  }

  Widget _keypadButton(String label, bool isDark,
      {bool isAction = false}) {
    return InkWell(
      onTap: () {
        if (label == 'backspace') {
          if (_otpController.text.isNotEmpty) {
            setState(() {
              _otpController.text = _otpController.text
                  .substring(0, _otpController.text.length - 1);
            });
          }
        } else {
          if (_otpController.text.length < 4) {
            setState(() {
              _otpController.text += label;
            });
          }
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Center(
          child: label == 'backspace'
              ? Icon(Icons.backspace_outlined,
                  size: 18, color: isDark ? Colors.white38 : Colors.black38)
              : Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
        ),
      ),
    );
  }
}
