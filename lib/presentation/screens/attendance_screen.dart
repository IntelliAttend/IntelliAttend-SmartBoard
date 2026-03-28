import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/totp_engine.dart';
import '../../services/firestore_service.dart';
import '../../services/session_manager.dart';
import '../widgets/attendance_grid.dart';
import '../widgets/attendance_timer.dart';
import '../widgets/qr_display_pane.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final String sessionSecret;
  final int rosterCount;
  final List<String> initialVerifiedIds;

  const AttendanceScreen({
    super.key, 
    required this.sessionId, 
    required this.sessionSecret,
    required this.rosterCount,
    this.initialVerifiedIds = const [],
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final TotpEngine _totpEngine;
  late final FirestoreService _firestoreService;
  
  String? _currentToken;
  double _qrProgress = 1.0;
  late List<String> _presentIds;
  bool _isSessionFinished = false;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _presentIds = List.from(widget.initialVerifiedIds);
    _initializeEngines();
  }

  Future<void> _initializeEngines() async {
    // 1. Kick off the TOTP Dart Isolate
    _totpEngine = TotpEngine(sessionSecret: widget.sessionSecret);
    
    _totpEngine.qrStream.listen((token) {
      if (!mounted || _isSessionFinished) return;
      setState(() {
        _currentToken = token;
        _qrProgress = 1.0; // Reset progress bar on 3.5s rotation
      });
    });

    await _totpEngine.start();

    // 2. Open the Firestore Stream
    _firestoreService = FirestoreService();
    _firestoreService.attendanceStream.listen((data) {
      if (!mounted) return;
      final studentId = data['student_id'] as String?;
      if (studentId != null && !_presentIds.contains(studentId)) {
        setState(() {
          _presentIds.add(studentId);
        });
        // PHASE 3: Persist verified student to local Isar Vault
        SessionManager.addVerifiedStudent(widget.sessionId, studentId);
      }
    });
    _firestoreService.startListening(widget.sessionId);

    // 3. Smooth QR Progress Animation (1.0 down to 0.0 over 3.5s)
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
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
    _totpEngine.stop();
    _progressTimer?.cancel();
    
    // PHASE 3: Wipe session from recovery vault when finished
    SessionManager.clearSession(widget.sessionId);
    print('✅ [Session] Sprint Complete. Recovery Vault Wiped.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left: Seating Grid (The Status Board)
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ATTENDANCE STATUS', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('${_presentIds.length}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.success)),
                            Text(' / ${widget.rosterCount} PRESENT', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Progress bar for total attendance
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: widget.rosterCount > 0 ? _presentIds.length / widget.rosterCount : 0,
                            minHeight: 12,
                            backgroundColor: AppColors.border,
                            color: AppColors.success,
                          ),
                        ),
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
          ),

          // Right: QR Vault (The Interaction Point)
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFF020617), // Deeper contrast for QR area
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('INTELLIATTEND', style: TextStyle(letterSpacing: 12, fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.primary)),
                      const SizedBox(height: 8),
                      const Text('DYNAMIC VERIFICATION STREAM', style: TextStyle(letterSpacing: 3, fontSize: 10, color: AppColors.textMuted)),
                      const SizedBox(height: 80),
                      
                      if (!_isSessionFinished) 
                        QRDisplayPane(token: _currentToken, progress: _qrProgress)
                      else
                        const Column(
                          children: [
                            Icon(Icons.verified_user_rounded, color: AppColors.success, size: 140),
                            SizedBox(height: 32),
                            Text('SESSION CLOSED', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            SizedBox(height: 12),
                            Text('AUTOMATED SPRINT COMPLETE', style: TextStyle(color: AppColors.textMuted, letterSpacing: 1)),
                          ],
                        ),
                      
                      const SizedBox(height: 80),
                      AttendanceTimer(
                        totalSeconds: 120,
                        onTimerFinished: _onAttendanceFinished,
                      ),
                      const SizedBox(height: 48),
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
    _firestoreService.stopListening();
    _progressTimer?.cancel();
    super.dispose();
  }
}
