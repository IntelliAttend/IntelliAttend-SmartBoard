import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../services/totp_engine.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/device_service.dart';
import '../widgets/glass_container.dart';
import 'idle_screen.dart';
import 'settings_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final String sessionSecret;
  final int capacity;
  final String courseName;
  final String facultyName;
  final List<String>? initialVerifiedIds;

  const AttendanceScreen({
    super.key,
    required this.sessionId,
    required this.sessionSecret,
    required this.capacity,
    required this.courseName,
    required this.facultyName,
    this.initialVerifiedIds,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with SingleTickerProviderStateMixin {
  late TotpEngine _totpEngine;
  String _currentQrData = '';
  late AnimationController _progressController;
  Timer? _qrRotationTimer;
  StreamSubscription<DocumentSnapshot>? _sessionStatusSubscription;
  bool _isSessionEnding = false;
  bool _qrRotationStopped = false;
  int _presentCount = 0;
  List<int> _presentSeatIndices = [];
  int _secondsRemaining = 900; // 15 minutes default
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    _totpEngine = TotpEngine(
      sessionId: widget.sessionId,
      sessionSecret: widget.sessionSecret,
    );
    
    _totpEngine.qrStream.listen((token) {
      if (mounted && !_qrRotationStopped) {
        setState(() => _currentQrData = token);
      }
    });

    _totpEngine.start();
    _qrRotationTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        setState(() => _qrRotationStopped = true);
        _totpEngine.stop();
        _progressController.stop();
      }
    });
    _startCountdown();
    _listenForSessionEnd();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTime(int seconds) {
    final mins = (seconds / 60).floor().toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  void _listenForSessionEnd() {
    if (Firebase.apps.isEmpty) return;
    _sessionStatusSubscription = FirebaseFirestore.instance
        .collection('sessions')
        .doc(widget.sessionId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (data?['status'] == 'ended' && !_isSessionEnding) {
        _handleSessionEnd();
      }
    });
  }

  void _handleSessionEnd() {
    if (_isSessionEnding) return;
    _isSessionEnding = true;
    _qrRotationTimer?.cancel();
    _totpEngine.stop();
    _progressController.stop();
    if (mounted) {
      SessionManager.clearSession(widget.sessionId);
      DeviceService.getRegistration().then((registration) {
        if (mounted && registration != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => IdleScreen(registration: registration)),
          );
        }
      });
    }
  }

  void _handlePhysicalTapEnd() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('End Session?', style: TextStyle(color: Colors.white)),
        content: Text(
          '$_presentCount students marked present. End "${widget.courseName}"?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.of(context).pop(); _handleEndAttendance(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _qrRotationTimer?.cancel();
    _countdownTimer?.cancel();
    _sessionStatusSubscription?.cancel();
    _totpEngine.stop();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _handleEndAttendance() async {
    try {
      await ApiService.terminateSession(widget.sessionId);
      SessionManager.clearSession(widget.sessionId);
      final registration = await DeviceService.getRegistration();
      if (mounted && registration != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => IdleScreen(registration: registration)),
        );
      }
    } catch (e) {
      setState(() => _isSessionEnding = false);
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
            opacity: isDark ? 0.08 : 0.05,
            child: Image.asset(
              'assets/background.png',
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
          _buildHeader(isDark),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: (Firebase.apps.isNotEmpty)
                  ? FirebaseFirestore.instance
                      .collection('ActiveSessions')
                      .doc(widget.sessionId)
                      .collection('attendees')
                      .orderBy('timestamp', descending: true)
                      .snapshots()
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final attendeeDocs = snapshot.data?.docs ?? [];
                _presentCount = attendeeDocs.length;
                
                // For demo/sim, we'll map student names to indices if they look like numbers
                // In production, this would be based on assigned seat IDs
                _presentSeatIndices = attendeeDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final id = data['student_id']?.toString() ?? '';
                  final match = RegExp(r'\d+').firstMatch(id);
                  return int.tryParse(match?.group(0) ?? '') ?? 0;
                }).where((i) => i > 0 && i <= widget.capacity).toList();

                return Row(
                  children: [
                    // LEFT: Seating Grid (40%)
                    Expanded(
                      flex: 4,
                      child: _buildSeatingSection(isDark),
                    ),
                    
                    // RIGHT: QR & Timer (60%)
                    Expanded(
                      flex: 6,
                      child: _buildQrArena(isDark, size),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildFooter(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Text(
            'IntelliAttend',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryTeal,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(width: 32),
          Container(width: 1, height: 24, color: isDark ? Colors.white10 : Colors.black12),
          const SizedBox(width: 24),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.courseName.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 4),
                  Text(widget.facultyName, style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
                  const SizedBox(width: 16),
                  Icon(Icons.meeting_room_outlined, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 4),
                  Text('Room 402', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none, size: 20)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.help_outline, size: 20)),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _handlePhysicalTapEnd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('End Session', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              CircleAvatar(
                radius: 18,
                backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                backgroundImage: const NetworkImage('https://lh3.googleusercontent.com/aida/ADBb0uiwHbFIJUsrGmJZjxX_QjiBzSRetE_oM9UggtEHQXa16Ph4BQhn8ZxMDBmStf_ETGbAy_SgSSNnJeFuVN13QYFO54EuukewgpMY3ItXI4vr0UWy1jZTjrqaPCzWhou76wYfQ9KyZolcxZtDw8aOU1YGQu7SV0StQ9gFPaoz6EDhXar_4Yj8ajMGUZUoz-hNK6FahApnXBQzbkfRe6ah1WO_GtY78ie_iykJ3w9xH74GmCV_9Ub-JFyhi0lvFoxMTjq3CBvoes14KA'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeatingSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
        border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 60,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: widget.capacity,
              itemBuilder: (context, index) {
                final seatNum = index + 1;
                final isPresent = _presentSeatIndices.contains(seatNum);
                return Container(
                  decoration: BoxDecoration(
                    color: isPresent 
                        ? (isDark ? AppColors.successLime.withValues(alpha: 0.1) : const Color(0xFFF1F9E6))
                        : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPresent 
                          ? AppColors.successLime 
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      width: isPresent ? 2 : 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      seatNum.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isPresent 
                            ? (isDark ? AppColors.successLime : const Color(0xFF1A2E05))
                            : (isDark ? Colors.white24 : const Color(0xFF94A3B8)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendItem('PRESENT', AppColors.successLime, isDark),
                const SizedBox(width: 32),
                _buildLegendItem('EMPTY', isDark ? Colors.white24 : const Color(0xFFE2E8F0), isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildQrArena(bool isDark, Size size) {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.successLime.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.successLime.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.successLime),
                ),
                const SizedBox(width: 10),
                const Text(
                  'LIVE SESSION ACTIVE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.successLime, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          
          // Pulsing QR Arena
          AnimatedBuilder(
            animation: _progressController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: AppColors.successLime.withValues(alpha: 0.2 + (0.3 * _progressController.value)),
                    width: 8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.successLime.withValues(alpha: 0.1 * _progressController.value),
                      blurRadius: 40 * _progressController.value,
                      spreadRadius: 10 * _progressController.value,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryTeal, Color(0xFF0D9488)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _currentQrData.isNotEmpty
                  ? QrImageView(
                      data: _currentQrData,
                      version: QrVersions.auto,
                      size: 320,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.white),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.white),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          
          const SizedBox(height: 48),
          Column(
            children: [
              const Text(
                'TIME REMAINING',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 3),
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(_secondsRemaining),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final attendanceRate = widget.capacity > 0 ? (_presentCount / widget.capacity * 100).toInt() : 0;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ATTENDANCE RATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 2)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_presentCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(' / ${widget.capacity}', style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.successLime.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('$attendanceRate%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.successLime)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 48),
          Container(width: 1, height: 24, color: isDark ? Colors.white10 : Colors.black12),
          const Spacer(),
          Row(
            children: [
              _buildAvatarStack(),
              const SizedBox(width: 12),
              const Text('142 Students Present', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarStack() {
    return SizedBox(
      width: 120,
      height: 32,
      child: Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=${i + 40}'),
                ),
              ),
            ),
          Positioned(
            left: 3 * 20.0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryTeal,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: Text('+29', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
