import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/student_service.dart';
import '../../services/websocket_service.dart';
import '../../services/heartbeat_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/utils/roll_number_utils.dart';
import '../../core/utils/logger.dart';
import 'summary_screen.dart';
import 'workspace_screen.dart';
import '../widgets/glass_container.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final int capacity;
  final String courseName;
  final String facultyName;
  final String roomName;
  final String? sectionId;
  final String? slotId;
  final String? boardId;

  final WebsocketService websocketService;
  final int initialPresentCount;

  const AttendanceScreen({
    super.key,
    required this.sessionId,
    required this.capacity,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    required this.websocketService,
    this.initialPresentCount = 0,
    this.sectionId,
    this.slotId,
    this.boardId,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Stage { grid, splitReview }

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  late WebsocketService _wsService;
  bool _isSessionEnding = false;
  int _presentCount = 0;
  int _totalStudents = 0;
  final Set<int> _presentSeatIndices = {};
  final Set<int> _absentSeatIndices = {};

  bool _isAttendanceSubmitted = false;
  bool _isSubmitting = false;

  static const int _endSessionCooldownSeconds = 7;
  bool _canEndSession = false;
  int _endSessionCountdown = _endSessionCooldownSeconds;
  Timer? _endSessionCooldownTimer;

  bool _isRosterLoaded = false;
  _Stage _stage = _Stage.grid;

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
    unawaited(_loadClassRoster());
    _restoreLocalSnapshot();

    _connectWebSocket();
  }

  Future<void> _loadClassRoster() async {
    final sectionId = widget.sectionId;
    if (sectionId == null || sectionId.isEmpty) {
      _isRosterLoaded = true;
      return;
    }
    try {
      final students = await StudentService().getStudentsBySection(sectionId);
      _students = students;
    } catch (e) {
      Log.w('[Attendance] Failed to load roster for section $sectionId: $e');
    }
    if (mounted) {
      setState(() {
        _totalStudents = _students.length;
        _isRosterLoaded = true;
      });
    }
  }

  Future<void> _restoreLocalSnapshot() async {
    final snapshot = await SessionManager.loadAttendanceSnapshot(widget.sessionId);
    if (snapshot != null && mounted) {
      final presentList = snapshot.$1;
      final absentList = snapshot.$2;
      if (mounted) {
        setState(() {
          _presentSeatIndices
            ..clear()
            ..addAll(presentList);
          _absentSeatIndices
            ..clear()
            ..addAll(absentList);
          _presentCount = presentList.length;
          if (presentList.isNotEmpty || absentList.isNotEmpty) {
            _stage = _Stage.splitReview;
          }
        });
      }
      Log.i('[Attendance] Restored local snapshot: ${presentList.length} present, ${absentList.length} absent');
    }
  }

  void _connectWebSocket() {
    _wsService.connectAttendance(widget.sessionId);

    _wsSyncSubscription = _wsService.onFullStateSync.listen((sync) {
      if (!mounted) return;
      setState(() {
        _presentSeatIndices.clear();
        int presentCount = 0;
        for (final student in sync.presentStudents) {
          if (student.status.toUpperCase() != 'PRESENT') continue;
          final key =
              (student.studentEmail ?? student.studentId).toLowerCase();
          int? index = _emailToSeatIndex[key];
          if (index == null) {
            final idx = _students.indexWhere(
                (s) => s.rollNumber == student.studentId);
            if (idx < 0 || idx >= _students.length) continue;
            index = idx;
          }
          final i = index;
          _presentSeatIndices.add(i);
          // Populate student name from sync data (§5)
          if (student.studentName.isNotEmpty &&
              _students[i].name.isEmpty) {
            _students[i] = StudentInfo(
              rollNumber: _students[i].rollNumber,
              name: student.studentName,
              email: student.studentEmail ?? student.studentId,
              sectionId: _students[i].sectionId,
              classId: _students[i].classId,
            );
          }
          presentCount++;
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
      int? index = _emailToSeatIndex[email];
      if (index == null) {
        final idx = _students.indexWhere((s) => s.rollNumber == event.studentId);
        if (idx < 0 || idx >= _students.length) {
          Log.d('[Attendance] student_verified: no seat match for ${event.studentId}');
          return;
        }
        index = idx;
      }
      final i = index;
      if (event.isAbsent) {
        setState(() {
          _absentSeatIndices.add(i);
          _presentSeatIndices.remove(i);
        });
      } else if (!_presentSeatIndices.contains(i)) {
          setState(() {
            _presentSeatIndices.add(i);
            _absentSeatIndices.remove(i);
            _pulsingSeatIndices.add(i);
          });
          _pulseTimer?.cancel();
          _pulseTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) {
              setState(() => _pulsingSeatIndices.clear());
            }
          });
        }
        // Populate student name from verified event (§5)
        if (event.studentName.isNotEmpty &&
            _students[i].name.isEmpty) {
          final student = _students[i];
          setState(() {
            _students[i] = StudentInfo(
              rollNumber: student.rollNumber,
              name: event.studentName,
              email: event.studentId,
              sectionId: student.sectionId,
              classId: student.classId,
            );
          });
        }
      Log.i(
          '[Attendance] student_verified: ${event.studentId} seat=${event.seat} status=${event.status}');
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
    final student = index < _students.length ? _students[index] : null;
    final boardId = widget.boardId ?? _wsService.boardId ?? '';

    if (_presentSeatIndices.contains(index)) {
      _presentSeatIndices.remove(index);
      _absentSeatIndices.add(index);
      _sendTap(student, 'absent', boardId);
    } else if (_absentSeatIndices.contains(index)) {
      _absentSeatIndices.remove(index);
    } else {
      _presentSeatIndices.add(index);
      _sendTap(student, 'present', boardId);
    }
    if (mounted) setState(() {});
  }

  void _sendTap(StudentInfo? student, String status, String boardId) {
    if (student == null || boardId.isEmpty) return;
    _wsService.sendTap(
      sessionId: widget.sessionId,
      studentId: student.email,
      status: status,
      boardId: boardId,
    );
  }

  void _handleSplitReviewTap(int index, bool isInPresent) {
    if (isInPresent) {
      _presentSeatIndices.remove(index);
      _absentSeatIndices.add(index);
    } else {
      _absentSeatIndices.remove(index);
      _presentSeatIndices.add(index);
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleSaveAttendance() async {
    if (_presentSeatIndices.isEmpty && _absentSeatIndices.isEmpty) return;
    await SessionManager.saveAttendanceSnapshot(
      sessionId: widget.sessionId,
      presentIndices: _presentSeatIndices.toList(),
      absentIndices: _absentSeatIndices.toList(),
    );
    if (_wsService.isConnected) {
      final presentEmails =
          _presentSeatIndices.map((i) => _students[i].email).toList();
      final absentEmails =
          _absentSeatIndices.map((i) => _students[i].email).toList();
      _wsService.saveDraft(
        sessionId: widget.sessionId,
        presentEmails: presentEmails,
        absentEmails: absentEmails,
      );
    }
    if (mounted) setState(() => _stage = _Stage.splitReview);
  }

  Future<void> _handleSubmitAttendance() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final presentEmails =
          _presentSeatIndices.map((i) => _students[i].email).toList();
      final absentEmails =
          _absentSeatIndices.map((i) => _students[i].email).toList();

      if (_wsService.isConnected) {
        _wsService.submitAttendance(
          sessionId: widget.sessionId,
          presentEmails: presentEmails,
          absentEmails: absentEmails,
        );
      } else {
        await ApiService.submitAttendance(
          sessionId: widget.sessionId,
          presentEmails: presentEmails,
          absentEmails: absentEmails,
        );
      }

      setState(() => _isAttendanceSubmitted = true);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => WorkspaceScreen(
            sessionId: widget.sessionId,
            courseName: widget.courseName,
            facultyName: widget.facultyName,
            roomName: widget.roomName,
            sectionId: widget.sectionId,
            slotId: widget.slotId,
            presentCount: _presentSeatIndices.length,
            totalCapacity: widget.capacity,
            students: _students,
            presentIndices: _presentSeatIndices.toList(),
            absentIndices: _absentSeatIndices.toList(),
            isAttendanceSubmitted: true,
          ),
        ),
      );
    } catch (e) {
      Log.e('[Attendance] Error submitting attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                                      letterSpacing: 1,
                                      fontSize: 13)),
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
          students: _students,
          presentIndices: _presentSeatIndices.toList(),
          absentIndices: _absentSeatIndices.toList(),
          isAttendanceSubmitted: _isAttendanceSubmitted,
        ),
      ),
    );
  }

  void _handlePhysicalTapEnd() {
    if (!_isAttendanceSubmitted) {
      _showSubmitFirstDialog();
      return;
    }
    _showEndSessionConfirmation();
  }

  void _showSubmitFirstDialog() {
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
                          color: AppColors.warningAmber.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_rounded,
                            color: AppColors.warningAmber, size: 32),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Submit Attendance First',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Attendance has been saved locally but not yet submitted to the server.\n\nPlease submit before ending the session.',
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
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _handleSubmitAttendance();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryTeal,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('SUBMIT NOW',
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

  void _showEndSessionConfirmation() {
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
                          color: AppColors.successLime.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.checklist_rounded,
                            color: AppColors.successLime, size: 32),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Attendance Submitted ✓',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_presentCount students marked present.\nEnd "${widget.courseName}"?',
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
    if (!_isAttendanceSubmitted) {
      _showSubmitFirstDialog();
      return;
    }
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
          students: _students,
          presentIndices: _presentSeatIndices.toList(),
          absentIndices: _absentSeatIndices.toList(),
          isAttendanceSubmitted: _isAttendanceSubmitted,
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
                      child: _stage == _Stage.grid
                          ? _buildInteractionGrid(isDark)
                          : _buildSplitReviewView(isDark),
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
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_rounded,
                color: AppColors.primaryTeal, size: 24),
          ),
          const SizedBox(width: 20),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.courseName.toUpperCase(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 13,
                      color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 4),
                  Text(widget.facultyName,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38)),
                  const SizedBox(width: 16),
                  Icon(Icons.meeting_room_outlined,
                      size: 13,
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
          if (_canEndSession)
            ElevatedButton(
              onPressed: _handlePhysicalTapEnd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text(
                'End Session',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(width: 16),
          CircleAvatar(
            radius: 18,
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
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

    const cellSize = 64.0;
    const cellGap = 6.0;
    const rowHeaderW = 44.0;
    const cols = _gridColumns;
    final rows = (itemCount / cols).ceil();
    final gridW = cols * cellSize + (cols - 1) * cellGap;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: SizedBox(
          width: rowHeaderW + 8 + gridW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: cellGap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: rowHeaderW,
                      height: cellSize,
                      child: GestureDetector(
                        onTapDown: (_) {
                          final start = row * cols;
                          final end = start + cols > itemCount ? itemCount : start + cols;
                          _handleRowTapDown(row, start, end);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                          ),
                          child: Center(
                            child: Text(
                              'R${row + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: gridW,
                      child: Wrap(
                        spacing: cellGap,
                        runSpacing: cellGap,
                        children: List.generate(cols, (col) {
                          final index = row * cols + col;
                          if (index >= itemCount) {
                            return const SizedBox(
                              width: cellSize, height: cellSize,
                            );
                          }
                          return _buildKeycapCell(index, isDark, cellSize);
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeycapCell(int index, bool isDark, double size) {
    final isPresent = _presentSeatIndices.contains(index);
    final isAbsent = _absentSeatIndices.contains(index);
    final student = index < _students.length ? _students[index] : null;
    final roll = student?.rollNumber ?? RollNumberUtils.generateSeatCode(index);

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isPresent) {
      bgColor = AppColors.successLime;
      borderColor = AppColors.successLime.withValues(alpha: 0.6);
      textColor = Colors.white;
    } else if (isAbsent) {
      bgColor = AppColors.error;
      borderColor = AppColors.error.withValues(alpha: 0.6);
      textColor = Colors.white;
    } else {
      bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
      borderColor = isDark ? Colors.white10 : const Color(0xFFCBD5E1);
      textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    }

    return GestureDetector(
      onTapDown: (_) => _handleCellTapDown(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isPresent || isAbsent ? 2.0 : 1.0),
        ),
        child: Center(
          child: Text(
            roll,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitReviewView(bool isDark) {
    final presentIndices = <int>[];
    final absentIndices = <int>[];

    for (int i = 0; i < _students.length; i++) {
      if (_presentSeatIndices.contains(i)) {
        presentIndices.add(i);
      } else if (_absentSeatIndices.contains(i)) {
        absentIndices.add(i);
      }
    }

    final hasNone = presentIndices.isEmpty && absentIndices.isEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final paneW = min(maxW * 0.92, 1200.0);

        return Center(
          child: SizedBox(
            width: paneW,
            height: maxH * 0.88,
            child: hasNone
                ? Center(
                    child: Text(
                      'No attendance recorded.',
                      style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildReviewPane(presentIndices, true, isDark),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: _buildReviewPane(absentIndices, false, isDark),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildReviewPane(List<int> indices, bool isPresent, bool isDark) {
    final accent = isPresent ? AppColors.successLime : AppColors.error;
    final bg = isPresent
        ? (isDark ? AppColors.successLime.withValues(alpha: 0.06) : const Color(0xFFF0FDF4))
        : (isDark ? AppColors.error.withValues(alpha: 0.06) : const Color(0xFFFEF2F2));

    if (indices.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text(
            'No ${isPresent ? "present" : "absent"} students',
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black26),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: accent.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(
                  '${isPresent ? "PRESENT" : "ABSENT"}  ·  ${indices.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  'tap to move',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: indices.map((index) {
                    final student = index < _students.length
                        ? _students[index]
                        : null;
                    final roll = student?.rollNumber ??
                        RollNumberUtils.generateSeatCode(index);
                    final name =
                        (student != null && student.name.isNotEmpty)
                            ? student.name
                            : 'Student ${index + 1}';
                    return GestureDetector(
                      onTap: () => _handleSplitReviewTap(index, isPresent),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  roll,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
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
    final hasMarked = presentLocal > 0 || absentCount > 0;

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
          if (_stage == _Stage.grid)
            ElevatedButton.icon(
              onPressed: hasMarked ? _handleSaveAttendance : null,
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('SAVE ATTENDANCE',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLime,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                minimumSize: const Size(180, 48),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          if (_stage == _Stage.splitReview)
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmitAttendance,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(_isSubmitting ? 'SUBMITTING...' : 'SUBMIT ATTENDANCE',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          if (_stage == _Stage.grid) const SizedBox(width: 24),
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

