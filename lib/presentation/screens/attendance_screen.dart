import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/student_service.dart';
import '../../services/websocket_service.dart';
import '../../services/heartbeat_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/utils/roll_number_utils.dart';
import '../../core/utils/logger.dart';
import 'summary_screen.dart';
import '../widgets/glass_container.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final int capacity;
  final String courseName;
  final String facultyName;
  final String roomName;
  final String? sectionId;
  final String? slotId;

  final WebsocketService websocketService;
  final String accessToken;
  final int initialPresentCount;

  const AttendanceScreen({
    super.key,
    required this.sessionId,
    required this.capacity,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    required this.websocketService,
    required this.accessToken,
    this.initialPresentCount = 0,
    this.sectionId,
    this.slotId,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  late WebsocketService _wsService;
  bool _isSessionEnding = false;
  int _presentCount = 0;
  int _totalStudents = 0;
  final Set<int> _presentSeatIndices = {};
  final Set<int> _absentSeatIndices = {};

  static const int _endSessionCooldownSeconds = 7;
  bool _canEndSession = false;
  int _endSessionCountdown = _endSessionCooldownSeconds;
  Timer? _endSessionCooldownTimer;

  bool _isRosterLoaded = false;
  bool _isCommitted = false;

  int _killSwitchJCount = 0;
  Timer? _killSwitchJTimer;
  final FocusNode _killSwitchFocusNode = FocusNode();

  List<StudentInfo> _students = [];
  final Map<String, int> _emailToSeatIndex = {};

  StreamSubscription? _wsAttendanceSubscription;
  StreamSubscription? _wsSyncSubscription;
  StreamSubscription? _wsSessionEndedSubscription;
  StreamSubscription? _wsStudentVerifiedSubscription;
  StreamSubscription? _wsAttendanceUpdatedSubscription;

  final Set<int> _pulsingSeatIndices = {};
  Timer? _pulseTimer;

  int _pendingTapIndex = -1;
  int _pendingRowTapIndex = -1;
  Timer? _tapTimer;

  static const int _gridColumns = 10;

  @override
  void initState() {
    super.initState();

    KioskService.setMode(KioskMode.locked);
    _wsService = widget.websocketService;
    _presentCount = widget.initialPresentCount;

    _startEndSessionCooldown();
    _loadClassRoster();

    _connectWebSocket();
  }

  void _loadClassRoster() {
    _students = List.generate(widget.capacity, (index) {
      final code = RollNumberUtils.generateSeatCode(index);
      return StudentInfo(
        rollNumber: code,
        name: '',
        email: '',
        sectionId: '',
        classId: '',
      );
    });
    _isRosterLoaded = true;
  }

  void _connectWebSocket() {
    _wsService.connectAttendance(widget.sessionId, widget.accessToken);

    _wsSyncSubscription = _wsService.onFullStateSync.listen((sync) {
      if (!mounted) return;
      setState(() {
        _presentSeatIndices.clear();
        int presentCount = 0;
        for (final student in sync.presentStudents) {
          if (student.status.toUpperCase() != 'PRESENT') continue;
          final email =
              (student.studentEmail ?? student.studentId).toLowerCase();
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
          _presentSeatIndices.add(index);
          _absentSeatIndices.remove(index);
        }
      });
      Log.i('[Attendance] WebSocket: ${event.studentId} marked present.');
    });

    _wsStudentVerifiedSubscription =
        _wsService.onStudentVerified.listen((event) {
      if (!mounted) return;
      final email = event.studentId.toLowerCase();
      final index = _emailToSeatIndex[email];
      if (index != null && !_presentSeatIndices.contains(index)) {
        setState(() {
          _presentSeatIndices.add(index);
          _absentSeatIndices.remove(index);
          _pulsingSeatIndices.add(index);
        });
        _pulseTimer?.cancel();
        _pulseTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() => _pulsingSeatIndices.clear());
          }
        });
      }
      Log.i(
          '[Attendance] student_verified: ${event.studentId} seat=${event.seat}');
    });

    _wsAttendanceUpdatedSubscription =
        _wsService.onAttendanceUpdated.listen((event) {
      if (!mounted) return;
      setState(() {
        _presentCount = event.present;
        _totalStudents =
            _totalStudents > 0 ? _totalStudents : event.present + event.absent;
      });
      Log.i(
          '[Attendance] Server update: ${event.present} present ${event.absent} absent');
    });

    _wsSessionEndedSubscription = _wsService.onSessionEnded.listen((event) {
      if (!mounted) return;
      Log.i('[Attendance] WebSocket: Session ended by server.');
      _handleSessionEnd();
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

  void _handleCellTapDown(int index) {
    _tapTimer?.cancel();
    if (_pendingTapIndex == index) {
      _pendingTapIndex = -1;
      if (_absentSeatIndices.contains(index)) {
        _absentSeatIndices.remove(index);
      } else {
        _absentSeatIndices.add(index);
        _presentSeatIndices.remove(index);
      }
      if (mounted) setState(() {});
    } else {
      _pendingTapIndex = index;
      _tapTimer = Timer(const Duration(milliseconds: 300), () {
        if (_pendingTapIndex == index) {
          _pendingTapIndex = -1;
          if (_presentSeatIndices.contains(index)) {
            _presentSeatIndices.remove(index);
          } else {
            _presentSeatIndices.add(index);
            _absentSeatIndices.remove(index);
          }
          if (mounted) setState(() {});
        }
      });
    }
  }

  void _handleRowTapDown(int rowIndex, int rowStart, int rowEnd) {
    _tapTimer?.cancel();
    if (_pendingRowTapIndex == rowIndex) {
      _pendingRowTapIndex = -1;
      for (int i = rowStart; i < rowEnd; i++) {
        _presentSeatIndices.add(i);
        _absentSeatIndices.remove(i);
      }
      if (mounted) setState(() {});
    } else {
      _pendingRowTapIndex = rowIndex;
      _tapTimer = Timer(const Duration(milliseconds: 300), () {
        _pendingRowTapIndex = -1;
      });
    }
  }

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
      if (_killSwitchJCount > 0) {
        _killSwitchJCount = 0;
        _killSwitchJTimer?.cancel();
      }
      return;
    }

    _killSwitchJCount++;
    _killSwitchJTimer?.cancel();

    if (_killSwitchJCount >= 3) {
      _killSwitchJCount = 0;
      _showKillSwitchConfirmation();
      return;
    }

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

  Future<void> _handleKillSwitch() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;
    Log.w('🚨 [KillSwitch] Emergency exit triggered by secret tap pattern.');
    _endSessionCooldownTimer?.cancel();
    await KioskService.executeAdministrativeShutdown();
  }

  Future<void> _handleSessionEnd() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;
    _endSessionCooldownTimer?.cancel();
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
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
    _wsStudentVerifiedSubscription?.cancel();
    _wsAttendanceUpdatedSubscription?.cancel();
    _pulseTimer?.cancel();
    _wsService.disconnect();

    _killSwitchJTimer?.cancel();
    _killSwitchFocusNode.dispose();
    _endSessionCooldownTimer?.cancel();
    _tapTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleEndAttendance() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;

    _endSessionCooldownTimer?.cancel();
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
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: _isCommitted
                          ? _buildResultsView(isDark)
                          : _buildInteractionGrid(isDark),
                    ),
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
    final absentCount = _absentSeatIndices.length;
    final total = _totalStudents > 0 ? _totalStudents : widget.capacity;
    final presentLocal = _presentSeatIndices.length;

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
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.successLime.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('$presentLocal / $total',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.successLime)),
                  ),
                  if (absentCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('$absentCount absent',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _canEndSession ? _handlePhysicalTapEnd : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _canEndSession
                  ? AppColors.primaryTeal
                  : Colors.grey,
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
                size: 20,
                color: isDark ? Colors.white54 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionGrid(bool isDark) {
    if (!_isRosterLoaded) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

    final itemCount = _students.length;
    if (itemCount == 0) {
      return Center(
        child: Text('No students in roster.',
            style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38)),
      );
    }

    final rows = (itemCount / _gridColumns).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        final rowHeaderW = 70.0;
        final gap = 6.0;
        final hPadding = 16.0;

        final usableW = min(maxW * 0.85, 1100.0) - rowHeaderW - hPadding * 2;
        final cellW = (usableW - gap * (_gridColumns - 1)) / _gridColumns;
        final cellH = min(cellW * 0.85, (maxH - 40) / rows);
        final gridW = rowHeaderW + hPadding * 2 + usableW;

        return SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: gridW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int row = 0; row < rows; row++) ...[
                    if (row > 0) SizedBox(height: gap),
                    _buildGridRow(row, rows, itemCount, cellW, cellH, gap,
                        rowHeaderW, isDark),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridRow(int row, int rows, int itemCount, double cellW,
      double cellH, double gap, double rowHeaderW, bool isDark) {
    final start = row * _gridColumns;
    final end = min(start + _gridColumns, itemCount);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: rowHeaderW,
          height: cellH,
          child: GestureDetector(
            onTapDown: (_) => _handleRowTapDown(row, start, end),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Center(
                child: Text(
                  '${row + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_gridColumns, (col) {
            final index = start + col;
            if (index >= itemCount) return SizedBox(width: cellW);
            return Padding(
              padding: EdgeInsets.only(right: col < _gridColumns - 1 ? gap : 0),
              child: _buildStudentCell(index, isDark, cellW, cellH),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildStudentCell(
      int index, bool isDark, double cellW, double cellH) {
    final isPresent = _presentSeatIndices.contains(index);
    final isAbsent = _absentSeatIndices.contains(index);
    final isPulsing = _pulsingSeatIndices.contains(index);
    final label = index < _students.length
        ? _students[index].rollNumber
        : RollNumberUtils.generateSeatCode(index);

    Color bgColor;
    Color borderColor;
    Color textColor;
    double borderWidth;

    if (isPresent) {
      bgColor = isDark
          ? AppColors.successLime.withValues(alpha: isPulsing ? 0.3 : 0.15)
          : (isPulsing
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFF1F9E6));
      borderColor = AppColors.successLime;
      borderWidth = isPulsing ? 3.0 : 2.0;
      textColor =
          isDark ? AppColors.successLime : const Color(0xFF1A2E05);
    } else if (isAbsent) {
      bgColor = isDark
          ? AppColors.error.withValues(alpha: 0.15)
          : AppColors.error.withValues(alpha: 0.08);
      borderColor = AppColors.error;
      borderWidth = 2.0;
      textColor =
          isDark ? Colors.red.shade300 : const Color(0xFF7F1D1D);
    } else {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.03)
          : const Color(0xFFF1F5F9);
      borderColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);
      borderWidth = 1.5;
      textColor =
          isDark ? Colors.white24 : const Color(0xFF94A3B8);
    }

    Widget cell = GestureDetector(
      onTapDown: (_) => _handleCellTapDown(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: cellW,
        height: cellH,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isPulsing
              ? [
                  BoxShadow(
                    color: AppColors.successLime.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );

    if (isPulsing) {
      cell = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 0.95),
        duration: const Duration(milliseconds: 600),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: 1.0 + (0.05 * (1.0 - scale)),
            child: child,
          );
        },
        child: cell,
      );
    }

    return cell;
  }

  Widget _buildResultsView(bool isDark) {
    final presentIndices = <int>[];
    final absentIndices = <int>[];

    for (int i = 0; i < _students.length; i++) {
      if (_presentSeatIndices.contains(i)) {
        presentIndices.add(i);
      } else if (_absentSeatIndices.contains(i)) {
        absentIndices.add(i);
      }
    }

    if (presentIndices.isEmpty && absentIndices.isEmpty) {
      return Center(
        child: Text('No attendance recorded.',
            style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final paneW = min(maxW * 0.9, 1200.0);
        final tileW = 80.0;
        final tileH = 70.0;
        final tileGap = 6.0;

        return Center(
          child: SizedBox(
            width: paneW,
            height: maxH * 0.85,
            child: Row(
              children: [
                Expanded(child: _buildResultPane(presentIndices, true, isDark,
                    tileW, tileH, tileGap)),
                Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black12,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                Expanded(
                    child: _buildResultPane(absentIndices, false, isDark,
                        tileW, tileH, tileGap)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultPane(List<int> indices, bool isPresent, bool isDark,
      double tileW, double tileH, double gap) {
    if (indices.isEmpty) {
      return Center(
        child: Text(
          isPresent ? 'No present' : 'No absent',
          style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white24 : Colors.black26),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                isPresent ? 'PRESENT' : 'ABSENT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: isPresent
                      ? AppColors.successLime
                      : AppColors.error,
                ),
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              childAspectRatio: tileW / tileH,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, slot) {
                final index = indices[slot];
                final label = index < _students.length
                    ? _students[index].rollNumber
                    : RollNumberUtils.generateSeatCode(index);
                return _AnimatedResultTile(
                  index: slot,
                  label: label,
                  isPresent: isPresent,
                  isDark: isDark,
                );
              },
              childCount: indices.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final total = _totalStudents > 0 ? _totalStudents : widget.capacity;
    final absentCount = _absentSeatIndices.length;
    final presentLocal = _presentSeatIndices.length;
    final unmarkedCount = total - presentLocal - absentCount;
    final attendanceRate =
        total > 0 ? (presentLocal / total * 100).toInt() : 0;

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
          _buildFooterBadge(
              'PRESENT', AppColors.successLime, '$presentLocal'),
          const SizedBox(width: 24),
          _buildFooterBadge('ABSENT', AppColors.error, '$absentCount'),
          if (unmarkedCount > 0) ...[
            const SizedBox(width: 24),
            _buildFooterBadge('UNMARKED', Colors.grey, '$unmarkedCount'),
          ],
          const SizedBox(width: 48),
          Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.white10 : Colors.black12),
          const Spacer(),
          if (!_isCommitted)
            ElevatedButton.icon(
              onPressed: () => setState(() => _isCommitted = true),
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text('COMMIT ATTENDANCE',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLime,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 44),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          if (!_isCommitted) const SizedBox(width: 24),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: attendanceRate >= 80
                  ? AppColors.successLime.withValues(alpha: 0.1)
                  : AppColors.warningAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '$attendanceRate% ATTENDING',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: attendanceRate >= 80
                    ? AppColors.successLime
                    : AppColors.warningAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterBadge(String label, Color color, String count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _AnimatedResultTile extends StatefulWidget {
  final int index;
  final String label;
  final bool isPresent;
  final bool isDark;

  const _AnimatedResultTile({
    required this.index,
    required this.label,
    required this.isPresent,
    required this.isDark,
  });

  @override
  State<_AnimatedResultTile> createState() => _AnimatedResultTileState();
}

class _AnimatedResultTileState extends State<_AnimatedResultTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    final fromX = widget.isPresent ? -0.2 : 0.2;
    _slideAnim = Tween<Offset>(
      begin: Offset(fromX, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    Future.delayed(Duration(milliseconds: widget.index * 30), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPresent = widget.isPresent;
    final isDark = widget.isDark;

    final bgColor = isPresent
        ? (isDark
            ? AppColors.successLime.withValues(alpha: 0.15)
            : const Color(0xFFF1F9E6))
        : (isDark
            ? AppColors.error.withValues(alpha: 0.15)
            : AppColors.error.withValues(alpha: 0.08));
    final borderColor = isPresent ? AppColors.successLime : AppColors.error;
    final textColor = isPresent
        ? (isDark ? AppColors.successLime : const Color(0xFF1A2E05))
        : (isDark ? Colors.red.shade300 : const Color(0xFF7F1D1D));

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
