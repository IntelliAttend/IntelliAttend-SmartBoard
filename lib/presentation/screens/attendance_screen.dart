
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/totp_engine.dart';
import '../../services/socket_service.dart';
import '../widgets/attendance_grid.dart';
import '../widgets/attendance_timer.dart';
import '../widgets/qr_display_pane.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final String sessionSecret;
  final int rosterCount;

  const AttendanceScreen({
    super.key, 
    required this.sessionId, 
    required this.sessionSecret,
    required this.rosterCount
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final TotpEngine _totpEngine;
  late final SocketService _socketService;
  
  String? _currentToken;
  double _qrProgress = 0.0;
  List<String> _presentIds = [];
  bool _isSessionFinished = false;

  @override
  void initState() {
    super.initState();
    _initializeEngines();
  }

  Future<void> _initializeEngines() async {
    // 1. Kick off the TOTP Dart Isolate
    _totpEngine = TotpEngine(sessionSecret: widget.sessionSecret);
    
    _totpEngine.qrStream.listen((token) {
      if (!mounted || _isSessionFinished) return;
      setState(() {
        _currentToken = token;
        _qrProgress = 1.0; // Reset visual progress bar on 3.5s rotation
      });
    });

    await _totpEngine.start();

    // 2. Open the WebSocket "Ear" to Node.js
    _socketService = SocketService();
    
    _socketService.attendanceStream.listen((data) {
      if (!mounted) return;
      final studentId = data['student_id'] as String?;
      if (studentId != null && !_presentIds.contains(studentId)) {
        setState(() {
          _presentIds.add(studentId);
        });
      }
    });

    _socketService.connect();

    // 3. Start smooth progressive degradation animation for UI (~3.5s cycle)
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isSessionFinished || !mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _qrProgress = (_qrProgress - (50 / 3500)).clamp(0.0, 1.0);
      });
    });
  }

  void _onAttendanceFinished() {
    setState(() => _isSessionFinished = true);
    _totpEngine.stop(); // Kills the Isolate instantly
    print('✅ [Session] 120-second window closed. QR Engine Terminated.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Section: Seating Grid
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ATTENDANCE STATUS', style: Theme.of(context).textTheme.bodyMedium?.copyWith(letterSpacing: 2)),
                      Text('${_presentIds.length} / ${widget.rosterCount} PRESENT', 
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.success)),
                    ],
                  ),
                ),
                Expanded(
                  child: AttendanceGrid(
                    verifiedIds: _presentIds,
                    totalCount: widget.rosterCount,
                  ),
                ),
              ],
            ),
          ),

          // Right Section: QR Focus
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFF05070A), // Blacker background for contrast
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 64),
                      const Text('INTELLIATTEND', style: TextStyle(letterSpacing: 12, fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 12),
                      const Text('DYNAMIC VERIFICATION STREAM', style: TextStyle(letterSpacing: 4, fontSize: 10, color: AppColors.textMuted)),
                      const SizedBox(height: 64),
                      
                      if (!_isSessionFinished) 
                        QRDisplayPane(token: _currentToken, progress: _qrProgress)
                      else
                        const Column(
                          children: [
                            Icon(Icons.check_circle_outline, color: AppColors.success, size: 120),
                            SizedBox(height: 24),
                            Text('WINDOW CLOSED', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      
                      const SizedBox(height: 64),
                      AttendanceTimer(
                        totalSeconds: 120, // Spec Section 4.2
                        onTimerFinished: _onAttendanceFinished,
                      ),
                      const SizedBox(height: 64),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _totpEngine.stop();
    _socketService.disconnect();
    super.dispose();
  }
}
