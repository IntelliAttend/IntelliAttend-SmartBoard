import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import 'attendance_screen.dart';

class KioskHomeScreen extends StatefulWidget {
  const KioskHomeScreen({super.key});

  @override
  State<KioskHomeScreen> createState() => _KioskHomeScreenState();
}

class _KioskHomeScreenState extends State<KioskHomeScreen> {
  final TextEditingController _otpController = TextEditingController();
  Map<String, dynamic>? _currentSchedule;
  bool _isLoading = true;
  bool _isSubmitting = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
    // Poll every 60 seconds to "wake up" when a class starts
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetchSchedule());
  }

  Future<void> _fetchSchedule() async {
    try {
      final schedule = await ApiService.getCurrentSchedule();
      if (mounted) {
        setState(() {
          _currentSchedule = schedule['has_class'] ? schedule : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Schedule Fetch Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtp() async {
    if (_otpController.text.length != 6) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await ApiService.initiateSession(_otpController.text);
      if (result['status'] == 'success') {
        final data = result['data'];
        
        await SessionManager.saveSession(
          sessionId: data['session_id'],
          rosterCount: data['roster_count'],
          facultyName: data['faculty_name'],
          endTime: DateTime.now().add(const Duration(hours: 1)),
        );

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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification Failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Row(
        children: [
          // Left: Institutional Branding / Clock
          Expanded(
            flex: 3,
            child: Container(
              color: AppColors.surface,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.school_rounded, size: 120, color: AppColors.primary),
                    const SizedBox(height: 32),
                    Text('INTELLIATTEND', style: Theme.of(context).textTheme.headlineLarge),
                    const Text('SMART CAMPUS INFRASTRUCTURE', style: TextStyle(letterSpacing: 4, color: AppColors.textMuted)),
                    const SizedBox(height: 64),
                    _buildDigitalClock(),
                  ],
                ),
              ),
            ),
          ),

          // Right: Dynamic "Wake Up" Area
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(48),
              child: _currentSchedule == null 
                ? _buildIdleView() 
                : _buildSessionReadyView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitalClock() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Text(
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200, color: AppColors.textPrimary),
        );
      },
    );
  }

  Widget _buildIdleView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.event_busy_rounded, size: 64, color: AppColors.textMuted),
        const SizedBox(height: 24),
        const Text('No Active Schedule', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('The board will automatically wake up when the next class is scheduled.', 
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _fetchSchedule,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('CHECK AGAIN'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionReadyView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SESSION READY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 16),
        Text(_currentSchedule!['course_name'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Professor: ${_currentSchedule!['faculty_name']}', style: const TextStyle(fontSize: 18, color: AppColors.textMuted)),
        const SizedBox(height: 48),
        const Divider(color: AppColors.border),
        const SizedBox(height: 48),
        const Text('FACULTY AUTHENTICATION', style: TextStyle(letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _otpController,
          maxLength: 6,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: '000000',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
          onChanged: (v) {
            if (v.length == 6) _submitOtp();
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isSubmitting 
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('START ATTENDANCE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }
}
