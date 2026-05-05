import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/hardware_fingerprint_service.dart';
import '../../services/session_manager.dart';
import 'attendance_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submitOtp() async {
    if (_otpController.text.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.initiateSession(_otpController.text);
      if (result['status'] == 'success' && result['data'] != null) {
        final data = result['data'];
        
        // --- PHASE 3: Persist session for Crash Recovery (v5.2 Secret-less) ---
        await SessionManager.saveSession(
          sessionId: data['session_id'],
          rosterCount: data['roster_count'],
          facultyName: data['room_name'] ?? 'Professor',
          endTime: DateTime.parse(data['server_time'] ?? DateTime.now().toIso8601String()).add(const Duration(hours: 1)),
        );

        await HardwareFingerprintService.maximizeBrightness();

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => AttendanceScreen(
                sessionId: data['session_id'],
                roomId: data['room_id'] ?? '402',
                sessionSecret: data['session_secret'],
                rosterCount: data['roster_count'],
              ),
            ),
          );
        }
      } else {
        setState(() => _errorMessage = 'Invalid response from server.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initiate session. Check network or OTP.';
      });
      print('Login Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 24),
              Text('Smart Board Login', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Enter 6-digit OTP from Faculty App', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              TextField(
                controller: _otpController,
                maxLength: 6,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '000000',
                  errorText: _errorMessage,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitOtp,
                  child: _isLoading 
                      ? const CircularProgressIndicator() 
                      : const Text('Initiate Session', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
