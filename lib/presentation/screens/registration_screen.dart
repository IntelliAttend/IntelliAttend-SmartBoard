import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_service.dart';
import '../../core/utils/logger.dart';
import '../widgets/glass_container.dart';
import 'boot_screen.dart';
import 'settings_screen.dart';
import '../../models/isar_schemas.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _roomIdController = TextEditingController();
  final _roomNameController = TextEditingController();
  final _buildingController = TextEditingController();
  final _departmentController = TextEditingController();
  final _rosterCountController = TextEditingController(text: '60');
  final _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOtpSent = false;
  String? _errorMessage;

  Future<void> _handleRequestOtp() async {
    if (_roomIdController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter a Room ID first.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await DeviceService.requestOtp(roomId: _roomIdController.text);
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
        roomId: _roomIdController.text,
        otp: _otpController.text,
        deviceName: _roomNameController.text,
        rosterCount: int.tryParse(_rosterCountController.text) ?? 60,
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
    _roomIdController.dispose();
    _roomNameController.dispose();
    _buildingController.dispose();
    _departmentController.dispose();
    _rosterCountController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700 || size.width < 1000;
    final horizontalPadding = size.width * 0.05;
    final verticalPadding = size.height * 0.05;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.background, Color(0xFF1E293B)],
              ),
            ),
          ),
          
          // Settings Button (Top Left)
          Positioned(
            top: 24,
            left: 24,
            child: FutureBuilder<DeviceRegistration?>(
              future: DeviceService.getRegistration(),
              builder: (context, snapshot) {
                return Tooltip(
                  message: 'System Settings',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        final reg = snapshot.data ?? DeviceRegistration()
                          ..roomId = 'UNREGISTERED'
                          ..roomName = 'New Device'
                          ..building = 'Unknown'
                          ..department = 'Unknown'
                          ..hardwareId = 'Unknown';
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SettingsScreen(registration: reg),
                          ),
                        );
                      },
                      child: GlassContainer(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 12,
                        child: const Icon(Icons.settings_outlined, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: isSmallScreen 
                      ? Column(
                          children: [
                            _buildContextSide(size, isSmallScreen: true),
                            const SizedBox(height: 32),
                            _buildFormSide(size, isSmallScreen: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left: Institutional Context
                            Expanded(
                              flex: 2,
                              child: _buildContextSide(size),
                            ),

                            SizedBox(width: size.width * 0.05),

                            // Right: Registration Form
                            Expanded(
                              flex: 3,
                              child: _buildFormSide(size),
                            ),
                          ],
                        ),
                  ),
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildContextSide(Size size, {bool isSmallScreen = false}) {
    return GlassContainer(
      padding: EdgeInsets.all(isSmallScreen ? 32 : 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.app_registration_rounded, size: (size.width * 0.05).clamp(40.0, 80.0), color: AppColors.primary),
          const SizedBox(height: 32),
          Text(
            'DEVICE\nREGISTRATION',
            style: TextStyle(
              fontSize: (size.width * 0.025).clamp(24, 48),
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Binding this SmartBoard to a physical classroom environment. This requires IT Administrator authorization.',
            style: TextStyle(
              fontSize: (size.width * 0.012).clamp(14, 18),
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 48),
          _buildGuideline(Icons.vpn_key_rounded, 'Step 1: Request a secure PIN for your classroom.', size),
          _buildGuideline(Icons.admin_panel_settings_rounded, 'Step 2: IT Admin authorizes the hardware link.', size),
          _buildGuideline(Icons.lock_clock_rounded, 'Step 3: Device is locked to the classroom bedrock.', size),
        ],
      ),
    );
  }

  Widget _buildFormSide(Size size, {bool isSmallScreen = false}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isSmallScreen ? double.infinity : 600),
        child: GlassContainer(
          padding: EdgeInsets.all(isSmallScreen ? 32 : 64),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) _buildErrorBanner(),
                Text(
                  'HARDWARE BINDING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _roomIdController,
                  label: 'Classroom ID',
                  hint: 'e.g. CR-402',
                  icon: Icons.meeting_room_rounded,
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
                  const SizedBox(height: 48),
                  Text(
                    'DEVICE DETAILS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildTextField(
                    controller: _roomNameController,
                    label: 'Board Display Name',
                    hint: 'e.g. CS Lab SmartBoard',
                    icon: Icons.title_rounded,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(controller: _buildingController, label: 'Building', hint: 'Block A', icon: Icons.corporate_fare_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField(controller: _rosterCountController, label: 'Capacity', hint: '60', icon: Icons.people_rounded, keyboardType: TextInputType.number)),
                    ],
                  ),
                ],
                const SizedBox(height: 64),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_isOtpSent ? _handleVerifyAndRegister : _handleRequestOtp),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isOtpSent ? 'VERIFY & BOND DEVICE' : 'REQUEST REGISTRATION PIN', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_isOtpSent)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _isOtpSent = false),
                      child: const Text('Change Room ID', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  Widget _buildGuideline(IconData icon, String text, Size size) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Icon(icon, size: (size.width * 0.015).clamp(20.0, 24.0), color: AppColors.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textMuted, fontSize: (size.width * 0.01).clamp(14, 16)))),
        ],
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
      validator: (v) => v == null || v.isEmpty ? 'Required field' : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
        prefixIcon: Icon(icon, color: AppColors.primary),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
      ),
    );
  }
}
