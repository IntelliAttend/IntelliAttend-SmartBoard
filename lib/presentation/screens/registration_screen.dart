import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../providers/registration_provider.dart';
import 'boot_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _smartBoardIdController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _smartBoardIdController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('Exit Application?'),
          ],
        ),
        content: const Text(
          'This device has not been registered yet.\n\nAre you sure you want to close IntelliAttend?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('STAY'),
          ),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXIT'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RegistrationProvider>(
      builder: (context, provider, child) {
        if (provider.step == RegistrationStep.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const BootScreen()),
            );
          });
        }

        return Scaffold(
          backgroundColor: AppColors.bgLight,
          body: Stack(
            children: [
              // 1. Uniform Background Pattern (matching BootScreen/IdleScreen)
              Opacity(
                opacity: 0.03,
                child: Center(
                  child: Image.asset(
                    'assets/background.png',
                    width: MediaQuery.of(context).size.width * 0.6,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // 2. Exit Button (top-right) — No PIN required.
              //    The device is NOT yet registered; there is nothing to protect.
              //    If an admin doesn't have credentials, they must be able to close the app.
              Positioned(
                top: 24,
                right: 24,
                child: Tooltip(
                  message: 'Exit Application',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _showExitDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.power_settings_new_rounded, size: 16, color: Colors.red.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Exit App',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 3. Main Content
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Container(
                      padding: const EdgeInsets.all(48),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 40,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: Colors.black.withOpacity(0.05)),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.security_rounded,
                                  size: 48, color: AppColors.primaryTeal),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              provider.step == RegistrationStep.otpSent
                                  ? 'BOND HARDWARE'
                                  : 'SYSTEM AUTHENTICATION',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimaryLight,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              provider.step == RegistrationStep.otpSent
                                  ? 'Verify identity to link this board.'
                                  : 'Authenticate with your SmartBoard ID.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 48),
                            if (provider.errorMessage != null)
                              _buildErrorBanner(provider.errorMessage!),
                            _buildTextField(
                              controller: _smartBoardIdController,
                              label: 'SmartBoard ID',
                              hint: 'e.g. IASB-XXXX',
                              icon: Icons.monitor_rounded,
                              enabled: provider.step == RegistrationStep.idle,
                            ),
                            const SizedBox(height: 24),
                            _buildTextField(
                              controller: _passwordController,
                              label: 'System Password',
                              hint: '••••••••',
                              icon: Icons.lock_outline_rounded,
                              enabled: provider.step == RegistrationStep.idle,
                              isPassword: true,
                            ),
                            if (provider.step == RegistrationStep.otpSent) ...[
                              const SizedBox(height: 24),
                              Text(
                                'Identity Verified. Please enter the PIN sent to:\n${provider.adminEmail ?? "IT Administrator"}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.primaryTeal,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _otpController,
                                  label: 'Administrative PIN',
                                  hint: 'Enter 6-digit OTP',
                                  icon: Icons.vpn_key_rounded,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.timer_outlined, size: 14, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Expires in: ${provider.formattedOtpTime}',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            const SizedBox(height: 48),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: provider.isLoading
                                    ? null
                                    : () {
                                        if (provider.step == RegistrationStep.otpSent) {
                                          if (_formKey.currentState!.validate()) {
                                            provider.verifyOtp(
                                                _smartBoardIdController.text,
                                                _otpController.text);
                                          }
                                        } else {
                                          if (_formKey.currentState!.validate()) {
                                            provider.login(
                                                _smartBoardIdController.text,
                                                _passwordController.text);
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryTeal,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: provider.isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : Text(
                                        provider.step == RegistrationStep.otpSent
                                            ? 'VERIFY & BOND DEVICE'
                                            : 'AUTHENTICATE SYSTEM',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1)),
                              ),
                            ),
                            if (provider.step == RegistrationStep.otpSent)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: TextButton(
                                  onPressed: provider.reset,
                                  child: const Text('Cancel & Start Over',
                                      style: TextStyle(
                                          color: AppColors.textSecondaryLight, fontSize: 13)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    int? maxLength,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      obscureText: isPassword,
      maxLength: maxLength,
      maxLengthEnforcement: maxLength != null
          ? MaxLengthEnforcement.enforced
          : MaxLengthEnforcement.none,
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      style:
          TextStyle(color: AppColors.textPrimaryLight, fontWeight: FontWeight.w600, fontFamily: GoogleFonts.inter().fontFamily),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondaryLight, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primaryTeal, size: 20),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryTeal, width: 2)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF1F5F9))),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
