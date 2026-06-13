import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../services/totp_engine.dart';
import '../../services/api_service.dart';
import '../../services/websocket_service.dart';
import '../../services/student_service.dart';
import '../../services/heartbeat_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/utils/roll_number_utils.dart';
import '../../core/utils/logger.dart';
import 'summary_screen.dart';
import '../widgets/glass_container.dart';
import '../widgets/fluid_qr_view.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final int capacity;
  final String courseName;
  final String facultyName;
  final String roomName;
  final String? sectionId;
  final String? slotId;
  final TotpEngine totpEngine;
  final WebsocketService websocketService;
  final String accessToken;
  final bool isOffline;

  const AttendanceScreen({
    super.key,
    required this.sessionId,
    required this.capacity,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    required this.totpEngine,
    required this.websocketService,
    required this.accessToken,
    this.sectionId,
    this.slotId,
    this.isOffline = false,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TotpEngine _totpEngine;
  // ignore: unused_field — kept for future WebSocket integration
  late WebsocketService _wsService;
  String _currentQrData = '';
  late AnimationController _progressController;
  bool _isSessionEnding = false;
  // ignore: prefer_final_fields - mutated when WS re-enabled
  int _presentCount = 0;
  int _totalStudents = 0;
  // ignore: prefer_final_fields - mutated when WS re-enabled
  Set<int> _presentSeatIndices = {};
  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  static const int _endSessionCooldownSeconds = 7;
  bool _canEndSession = false;
  int _endSessionCountdown = _endSessionCooldownSeconds;
  Timer? _endSessionCooldownTimer;

  bool _isRosterLoaded = false;

  // Kill switch: Ctrl+Shift held + triple-J to escape absoluteLocked mode
  int _killSwitchJCount = 0;
  Timer? _killSwitchJTimer;
  final FocusNode _killSwitchFocusNode = FocusNode();

  List<StudentInfo> _students = [];
  final Map<String, int> _emailToSeatIndex = {};

  // WebSocket subscriptions
  StreamSubscription? _wsAttendanceSubscription;
  StreamSubscription? _wsSyncSubscription;
  StreamSubscription? _wsSessionEndedSubscription;

  @override
  void initState() {
    super.initState();

    KioskService.setMode(KioskMode.absoluteLocked);
    _totpEngine = widget.totpEngine;
    _wsService = widget.websocketService;

    // v6.4: The session countdown is the total window duration (e.g. 5–10 min),
    // NOT the 30s rotation interval.
    _secondsRemaining = _totpEngine.windowDuration.inSeconds;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    _totpEngine.qrStream.listen((token) {
      if (mounted) {
        setState(() => _currentQrData = token);
      }
    }, onError: (e) {
      Log.e('[Attendance] TOTP stream error: $e');
    });

    _totpEngine.start();
    _startCountdown();
    _startEndSessionCooldown();
    _loadClassRoster();

    // Hook up WebSocket for real-time sync.
    _connectWebSocket();
  }

  void _connectWebSocket() {
    _wsService.connect(widget.sessionId, widget.accessToken);

    _wsSyncSubscription = _wsService.onFullStateSync.listen((sync) {
      if (!mounted) return;
      setState(() {
        _presentSeatIndices.clear();
        int presentCount = 0;
        for (final student in sync.presentStudents) {
          if (student.status.toUpperCase() != 'PRESENT') continue;
          final email = (student.studentEmail ?? student.studentId).toLowerCase();
          final index = _emailToSeatIndex[email];
          if (index != null) {
            _presentSeatIndices.add(index);
            presentCount++;
          }
        }
        _presentCount = presentCount;
        _totalStudents = sync.totalStudents;
      });
      Log.i(
          '[Attendance] Full state sync: $_presentCount present / ${sync.totalStudents} total.');
    });

    _wsAttendanceSubscription = _wsService.onAttendanceMarked.listen((event) {
      if (!mounted) return;
      setState(() {
        final email = (event.studentEmail ?? event.studentId).toLowerCase();
        final index = _emailToSeatIndex[email];
        if (index != null) {
          if (!_presentSeatIndices.contains(index)) {
            _presentSeatIndices.add(index);
            _presentCount++;
          }
        }
      });
      Log.i('[Attendance] WebSocket: ${event.studentId} marked present.');
    });

    _wsSessionEndedSubscription = _wsService.onSessionEnded.listen((event) {
      if (!mounted) return;
      Log.i('[Attendance] WebSocket: Session ended by server.');
      _handleSessionEnd();
    });
  }

  /// Loads students and builds a mapping of Email -> Seat Index.
  /// This allows the board to know which grid box to highlight when the database updates.
  Future<void> _loadClassRoster() async {
    if (!mounted) return;

    if (widget.sectionId != null && widget.sectionId!.isNotEmpty) {
      try {
        final students =
            await StudentService().getStudentsBySection(widget.sectionId!);
        if (mounted && students.isNotEmpty) {
          setState(() {
            _students = students;
            _emailToSeatIndex.clear();
            // Map emails to indices 0..N
            for (int i = 0; i < students.length; i++) {
              final email = students[i].email.trim().toLowerCase();
              if (email.isNotEmpty) {
                _emailToSeatIndex[email] = i;
              }
            }
            _isRosterLoaded = true;
          });
          Log.i(
              '[Attendance] Loaded ${_students.length} students for display.');
          return;
        }
      } catch (e) {
        Log.w('[Attendance] Failed to load students, using fallback: $e');
      }
    }
    // Fallback if no sectionId or fetch failed
    _generateFallbackRoster();
  }

  void _generateFallbackRoster() {
    if (mounted) {
      setState(() {
        _students = List.generate(widget.capacity, (index) {
          final code = RollNumberUtils.generateSeatCode(index);
          return StudentInfo(
            rollNumber: code,
            name: 'Seat $code',
            email: '',
            sectionId: '',
            classId: '',
          );
        });
        _isRosterLoaded = true;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        // v6.4: On timer zero, we automatically end the locked session
        if (!_isSessionEnding) {
          Log.i('⏰ [Attendance] Countdown hit zero. Terminating session.');
          _handleEndAttendance();
        }
      }
    });
  }

  void _startEndSessionCooldown() {
    _endSessionCooldownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_endSessionCountdown > 0) {
        if (mounted) setState(() => _endSessionCountdown--);
      } else {
        timer.cancel();
        if (mounted) setState(() => _canEndSession = true);
      }
    });
  }

  String _formatTime(int seconds) {
    final mins = (seconds / 60).floor().toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  /// Secret kill switch: hold Ctrl+Shift and press J three times
  /// within 3 seconds to trigger emergency exit from absoluteLocked mode.
  void _onKillSwitchKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final ctrl = HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.controlRight);
    final shift = HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
    final isJ = event.logicalKey == LogicalKeyboardKey.keyJ;

    if (!ctrl || !shift || !isJ) {
      // If user releases modifiers or presses wrong key, reset counter
      if (_killSwitchJCount > 0) {
        _killSwitchJCount = 0;
        _killSwitchJTimer?.cancel();
      }
      return;
    }

    // Ctrl+Shift+J detected
    _killSwitchJCount++;
    _killSwitchJTimer?.cancel();

    if (_killSwitchJCount >= 3) {
      _killSwitchJCount = 0;
      _showKillSwitchConfirmation();
      return;
    }

    // Reset counter if next J doesn't come within 3 seconds
    _killSwitchJTimer = Timer(const Duration(seconds: 3), () {
      _killSwitchJCount = 0;
    });
  }

  void _showKillSwitchConfirmation() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  width: 420,
                  padding: const EdgeInsets.all(32),
                  borderRadius: 24,
                  color: Colors.black.withValues(alpha: 0.9),
                  borderColor: AppColors.error.withValues(alpha: 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 40),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'EMERGENCY EXIT',
                        style: TextStyle(
                            color: AppColors.error,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'This will immediately terminate the current session\nand exit the locked kiosk mode.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('CANCEL',
                                  style: TextStyle(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _handleKillSwitch();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('EMERGENCY EXIT',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Emergency kill switch: performs a cascading application teardown and
  /// terminates the process cleanly.
  Future<void> _handleKillSwitch() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;

    Log.w('🚨 [KillSwitch] Emergency exit triggered by secret tap pattern.');

    _countdownTimer?.cancel();
    _endSessionCooldownTimer?.cancel();
    _totpEngine.stop();
    _progressController.stop();

    await KioskService.executeAdministrativeShutdown();
  }

  // ignore: unused_element — reserved for WebSocket reconnection
  Future<void> _handleSessionEnd() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;
    _countdownTimer?.cancel();
    _totpEngine.stop();
    _progressController.stop();
    KioskService.setMode(KioskMode.fullscreen);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SummaryScreen(
          sessionId: widget.sessionId,
          presentCount: _presentCount,
          totalCapacity: widget.capacity,
          courseName: widget.courseName,
          facultyName: widget.facultyName,
          slotId: widget.slotId,
        ),
      ),
    );
  }

  void _handlePhysicalTapEnd() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  borderRadius: 24,
                  color: Colors.black.withValues(alpha: 0.8),
                  borderColor: Colors.white10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 32),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'End Session?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$_presentCount students marked present.\nAre you sure you want to end "${widget.courseName}"?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('CANCEL',
                                  style: TextStyle(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _handleEndAttendance();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('END SESSION',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _wsAttendanceSubscription?.cancel();
    _wsSyncSubscription?.cancel();
    _wsSessionEndedSubscription?.cancel();
    _wsService.disconnect();

    _killSwitchJTimer?.cancel();
    _killSwitchFocusNode.dispose();
    _countdownTimer?.cancel();
    _endSessionCooldownTimer?.cancel();
    _totpEngine.stop();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _handleEndAttendance() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;

    _countdownTimer?.cancel();
    _totpEngine.stop();
    _progressController.stop();
    KioskService.setMode(KioskMode.fullscreen);

    try {
      await ApiService.terminateSession(widget.sessionId);
    } catch (e) {
      Log.e('[Attendance] Error ending session: $e');
      HeartbeatService.enqueuePendingTermination(widget.sessionId);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SummaryScreen(
          sessionId: widget.sessionId,
          presentCount: _presentCount,
          totalCapacity: widget.capacity,
          courseName: widget.courseName,
          facultyName: widget.facultyName,
          slotId: widget.slotId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    return KeyboardListener(
      focusNode: _killSwitchFocusNode,
      autofocus: true,
      onKeyEvent: _onKillSwitchKeyEvent,
      child: Scaffold(
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
            Column(
              children: [
                _buildHeader(isDark),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildSeatingSection(isDark),
                      ),
                      Expanded(
                        flex: 6,
                        child: _buildQrArena(isDark, size),
                      ),
                    ],
                  ),
                ),
                _buildFooter(isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
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
          Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.white10 : Colors.black12),
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
                  Icon(Icons.person_outline,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 4),
                  Text(widget.facultyName,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38)),
                  const SizedBox(width: 16),
                  Icon(Icons.meeting_room_outlined,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 4),
                  Text(widget.roomName,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none, size: 20)),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.help_outline, size: 20)),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _canEndSession ? _handlePhysicalTapEnd : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _canEndSession ? AppColors.primaryTeal : Colors.grey,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _canEndSession
                      ? 'End Session'
                      : 'End Session (${_endSessionCountdown}s)',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              CircleAvatar(
                radius: 18,
                backgroundColor: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05),
                child: Icon(Icons.person,
                    size: 20, color: isDark ? Colors.white54 : Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeatingSection(bool isDark) {
    if (!_isRosterLoaded) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.5),
          border: Border(
              right:
                  BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              'Fetching Class Roster...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.5),
        border: Border(
            right: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
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
              itemCount: _totalStudents > 0 ? _totalStudents : widget.capacity,
              itemBuilder: (context, index) {
                // Determine if this seat is present
                final isPresent = _presentSeatIndices.contains(index);

                // Get display info for this seat
                final isLoaded = index < _students.length;
                final displayLabel = isLoaded
                    ? _students[index].rollNumber
                    : RollNumberUtils.generateSeatCode(index);

                return Container(
                  decoration: BoxDecoration(
                    color: isPresent
                        ? (isDark
                            ? AppColors.successLime.withValues(alpha: 0.1)
                            : const Color(0xFFF1F9E6))
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPresent
                          ? AppColors.successLime
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      width: isPresent ? 2 : 1.5,
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isPresent
                              ? (isDark
                                  ? AppColors.successLime
                                  : const Color(0xFF1A2E05))
                              : (isDark
                                  ? Colors.white24
                                  : const Color(0xFF94A3B8)),
                        ),
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
              color:
                  isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendItem('PRESENT', AppColors.successLime, isDark),
                const SizedBox(width: 32),
                _buildLegendItem('EMPTY',
                    isDark ? Colors.white24 : const Color(0xFFE2E8F0), isDark),
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
              border: Border.all(
                  color: AppColors.successLime.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.successLime),
                ),
                const SizedBox(width: 10),
                const Text(
                  'LIVE SESSION ACTIVE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.successLime,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // Pulsing QR Arena with white quiet zone for optimal scanning
          AnimatedBuilder(
            animation: _progressController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: AppColors.successLime.withValues(
                        alpha: 0.2 + (0.3 * _progressController.value)),
                    width: 8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.successLime
                          .withValues(alpha: 0.1 * _progressController.value),
                      blurRadius: 40 * _progressController.value,
                      spreadRadius: 10 * _progressController.value,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(24),
              child: _currentQrData.isNotEmpty
                  ? FluidQrView(
                      data: _currentQrData,
                      size: 320,
                      color: Colors.black,
                    )
                  : const CircularProgressIndicator(color: Colors.black54),
            ),
          ),

          const SizedBox(height: 48),
          Column(
            children: [
              const Text(
                'TIME REMAINING',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 3),
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
    final total = _totalStudents > 0 ? _totalStudents : widget.capacity;
    final attendanceRate = total > 0
        ? (_presentCount / total * 100).toInt()
        : 0;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        border: Border(
            top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ATTENDANCE RATE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 2)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_presentCount',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(' / ${total}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.successLime.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('$attendanceRate%',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.successLime)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 48),
          Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.white10 : Colors.black12),
          const Spacer(),
          Row(
            children: [
              _buildAvatarStack(),
              const SizedBox(width: 12),
              Text('$_presentCount Students Present',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarStack() {
    final displayed = _students.take(3).toList();
    final remaining = _students.length > 3 ? _students.length - 3 : 0;

    return SizedBox(
      width: 120,
      height: 32,
      child: Stack(
        children: [
          for (var i = 0; i < displayed.length; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: _avatarColor(i),
                  child: Text(
                    _initials(displayed[i].name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (remaining > 0)
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
                child: Center(
                  child: Text('+$remaining',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _avatarColor(int index) {
    const colors = [Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFFFF9800)];
    return colors[index % colors.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
