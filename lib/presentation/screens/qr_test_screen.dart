import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/totp_engine.dart';
import '../widgets/fluid_qr_view.dart';
import '../widgets/glass_container.dart';
import 'package:google_fonts/google_fonts.dart';

class QrTestScreen extends StatefulWidget {
  const QrTestScreen({super.key});

  @override
  State<QrTestScreen> createState() => _QrTestScreenState();
}

class _QrTestScreenState extends State<QrTestScreen> {
  final TextEditingController _sessionIdController = TextEditingController(text: 'TEST_SESSION_123');
  final TextEditingController _secretController = TextEditingController(text: 'test_secret_key_456');
  
  TotpEngine? _totpEngine;
  String _currentQrData = '';
  bool _isRunning = false;
  bool _isOffline = false;

  @override
  void dispose() {
    _totpEngine?.stop();
    _sessionIdController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _toggleEngine() {
    if (_isRunning) {
      _totpEngine?.stop();
      setState(() {
        _isRunning = false;
        _currentQrData = '';
      });
    } else {
      final sid = _sessionIdController.text.trim();
      final secret = _secretController.text.trim();

      if (sid.isEmpty || secret.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter Session ID and Secret')),
        );
        return;
      }

      _totpEngine = TotpEngine(
        sessionId: sid,
        sessionSecret: secret,
        isOffline: _isOffline,
      );

      _totpEngine!.qrStream.listen((token) {
        if (mounted) {
          setState(() => _currentQrData = token);
        }
      });

      _totpEngine!.start();
      setState(() => _isRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: const Text('QR Integration Diagnostic', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
      ),
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Panel: Configuration
            Expanded(
              flex: 4,
              child: GlassContainer(
                padding: const EdgeInsets.all(32),
                borderRadius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SESSION CONFIGURATION',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    _buildTextField('Session ID', _sessionIdController, enabled: !_isRunning),
                    const SizedBox(height: 24),
                    _buildTextField('Session Secret', _secretController, enabled: !_isRunning),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Checkbox(
                          value: _isOffline,
                          onChanged: _isRunning ? null : (v) => setState(() => _isOffline = v ?? false),
                          activeColor: AppColors.primaryTeal,
                        ),
                        const Text('Simulate Offline Mode', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _toggleEngine,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRunning ? AppColors.error : AppColors.primaryTeal,
                        ),
                        child: Text(
                          _isRunning ? 'STOP DIAGNOSTIC' : 'START GENERATION',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 40),
            // Right Panel: Output
            Expanded(
              flex: 6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          if (_isRunning)
                            BoxShadow(
                              color: AppColors.primaryTeal.withValues(alpha: 0.2),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                        ],
                      ),
                      child: _isRunning && _currentQrData.isNotEmpty
                          ? FluidQrView(
                              data: _currentQrData,
                              size: 400,
                              color: Colors.black,
                            )
                          : Container(
                              width: 400,
                              height: 400,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.qr_code_2_rounded, size: 100, color: Colors.grey),
                            ),
                    ),
                    const SizedBox(height: 40),
                    if (_isRunning) ...[
                      const Text(
                        'RAW PAYLOAD',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentQrData,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}
