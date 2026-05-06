import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_service.dart';
import 'boot_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _smartBoardIdController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOtpSent = false;
  String? _errorMessage;

  Future<void> _handleRequestOtp() async {
    if (_smartBoardIdController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter a SmartBoard ID first.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await DeviceService.requestOtp(smartBoardId: _smartBoardIdController.text);
      setState(() => _isOtpSent = true);
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyAndRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await DeviceService.registerWithOtp(
        smartBoardId: _smartBoardIdController.text,
        otp: _otpController.text,
        deviceName: 'SmartBoard ${_smartBoardIdController.text}',
        rosterCount: 60,
      );
      await DeviceService.syncTimetable();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const BootScreen()),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _smartBoardIdController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.app_registration_rounded, size: 48, color: AppColors.primary),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'DEVICE REGISTRATION',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bind this hardware to your institution.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    ),
                    const SizedBox(height: 48),
                    if (_errorMessage != null) _buildErrorBanner(),
                    _buildTextField(
                      controller: _smartBoardIdController,
                      label: 'SmartBoard ID',
                      hint: 'e.g. IASB-4208',
                      icon: Icons.monitor_rounded,
                      enabled: !_isOtpSent,
                    ),
                    if (_isOtpSent) ...[
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _otpController,
                        label: 'Administrative PIN',
                        hint: 'Enter 6-digit OTP',
                        icon: Icons.security_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : (_isOtpSent ? _handleVerifyAndRegister : _handleRequestOtp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isOtpSent ? 'VERIFY & BOND DEVICE' : 'REQUEST REGISTRATION PIN', 
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1)
                            ),
                      ),
                    ),
                    if (_isOtpSent)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TextButton(
                          onPressed: () => setState(() => _isOtpSent = false),
                          child: Text('Use different SmartBoard ID', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Color(0xFFF1F5F9))),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
