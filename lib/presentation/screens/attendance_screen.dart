import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/student_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/utils/roll_number_utils.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../main.dart' show kPreviewAttendance;
import 'summary_screen.dart';
import 'workspace_screen.dart';
import '../widgets/glass_container.dart';

class AttendanceScreen extends StatefulWidget {
  final String sessionId;
  final int capacity;
  final String courseName;
  final String facultyName;
  final String roomName;
  final String? slotId;
  final String? boardId;
  final String? courseCode;

  final int initialPresentCount;
  final List<int>? previousPresentIndices;
  final List<int>? previousAbsentIndices;
  final VoidCallback? onNavigateBack;

  const AttendanceScreen({
    super.key,
    required this.sessionId,
    required this.capacity,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    this.initialPresentCount = 0,
    this.previousPresentIndices,
    this.previousAbsentIndices,
    this.slotId,
    this.boardId,
    this.courseCode,
    this.onNavigateBack,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Stage { grid, splitReview }

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
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

  List<_StudentEntry> _students = [];

  OverlayEntry? _studentInfoOverlay;
  AnimationController? _cellPulseController;
  Animation<double>? _cellPulseAnimation;

  static const int _gridColumns = 10;

  @override
  void initState() {
    super.initState();

    _cellPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _cellPulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _cellPulseController!, curve: Curves.easeOut),
    );

    if (kPreviewAttendance) {
      // Preview mode: skip kiosk, use mock students
      _students = defaultMockStudents();
      _presentCount = widget.initialPresentCount;
      _totalStudents = _students.length;
      _isRosterLoaded = true;
    } else {
      KioskService.setMode(KioskMode.locked);
      _presentCount = widget.initialPresentCount;
      _startEndSessionCooldown();
      unawaited(_loadClassRoster());
      _restoreLocalSnapshot().catchError((e) {
        Log.w('[Attendance] Snapshot restore skipped: $e');
      });
      // Fallback: if snapshot is empty but previous indices were passed (e.g. from
      // WorkspaceScreen), initialise the grid from them so edits can continue.
      if (widget.previousPresentIndices != null || widget.previousAbsentIndices != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _presentSeatIndices.isEmpty && _absentSeatIndices.isEmpty) {
            setState(() {
              _presentSeatIndices.addAll(widget.previousPresentIndices ?? []);
              _absentSeatIndices.addAll(widget.previousAbsentIndices ?? []);
              _presentCount = _presentSeatIndices.length;
              if (_presentSeatIndices.isNotEmpty || _absentSeatIndices.isNotEmpty) {
                _stage = _Stage.splitReview;
              }
            });
          }
        });
      }
    }
  }

  static List<_StudentEntry> defaultMockStudents() {
    return List.generate(40, (i) => _StudentEntry(
      studentId: 'stu-${(i + 1).toString().padLeft(3, '0')}',
      name: 'Student ${i + 1}',
      rollNumber: RollNumberUtils.generateSeatCode(i),
    ));
  }

  Future<void> _loadClassRoster() async {
    try {
      final isar = SessionManager.isar;
      final allRosters = await isar.hydrationRosters.where().findAll();

      final seen = <String>{};
      final unique = <_StudentEntry>[];
      for (final r in allRosters) {
        if (r.studentId.isNotEmpty && seen.add(r.studentId)) {
          unique.add(_StudentEntry(
            studentId: r.studentId,
            name: r.name,
            rollNumber: r.rollNumber ?? '',
          ));
        }
      }
      unique.sort((a, b) => RollNumberUtils.compareRollNumber(a.rollNumber, b.rollNumber));
      _students = unique;

      Log.i('[Attendance] Loaded ${_students.length} unique students from hydration roster');
    } catch (e) {
      Log.w('[Attendance] Failed to load roster from hydration: $e');
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

  void _handleCellTapDown(int index) {
    _dismissStudentInfo();
    // Lock cells after attendance has been submitted to prevent post-submit
    // edits that would desync the local grid from the server state.
    if (_isAttendanceSubmitted) return;
    if (_presentSeatIndices.contains(index)) {
      _presentSeatIndices.remove(index);
      _absentSeatIndices.add(index);
    } else if (_absentSeatIndices.contains(index)) {
      _absentSeatIndices.remove(index);
    } else {
      _presentSeatIndices.add(index);
    }
    if (mounted) setState(() {});
  }

  void _showStudentInfo(int index, BuildContext cellContext) {
    _dismissStudentInfo();
    if (index >= _students.length) return;

    final student = _students[index];
    final roll = RollNumberUtils.formatDisplay(
        student.rollNumber.isNotEmpty ? student.rollNumber : RollNumberUtils.generateSeatCode(index));

    _cellPulseController?.forward(from: 0).then((_) => _cellPulseController?.reverse());

    final renderBox = cellContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final cellPosition = renderBox.localToGlobal(Offset.zero);
    final cellSize = renderBox.size;

    _studentInfoOverlay = OverlayEntry(
      builder: (context) => _StudentInfoBubble(
        studentName: student.name.isNotEmpty ? student.name : 'Student ${index + 1}',
        rollDisplay: roll,
        cellPosition: cellPosition,
        cellSize: cellSize,
      ),
    );

    Overlay.of(context).insert(_studentInfoOverlay!);
  }

  void _dismissStudentInfo() {
    _studentInfoOverlay?.remove();
    _studentInfoOverlay = null;
  }

  void _handleSplitReviewTap(int index, bool isInPresent) {
    if (_isAttendanceSubmitted) return;
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
    if (!kPreviewAttendance) {
      await SessionManager.saveAttendanceSnapshot(
        sessionId: widget.sessionId,
        presentIndices: _presentSeatIndices.toList(),
        absentIndices: _absentSeatIndices.toList(),
      );
    }
    if (mounted) setState(() => _stage = _Stage.splitReview);
  }

  Future<void> _handleSubmitAttendance() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final presentIds =
          _presentSeatIndices.map((i) => _students[i].studentId).toList();
      // All students NOT present are absent — ensures unmarked students
      // are explicitly recorded as absent on the server.
      final absentIds = _students
          .where((s) => !_presentSeatIndices.contains(_students.indexOf(s)))
          .map((s) => s.studentId)
          .toList();

      await ApiService.submitAttendance(
        sessionId: widget.sessionId,
        presentEmails: presentIds,
        absentEmails: absentIds,
      );

      // Persist snapshot after successful submit so re-entry restores latest state
      if (!kPreviewAttendance) {
        await SessionManager.saveAttendanceSnapshot(
          sessionId: widget.sessionId,
          presentIndices: _presentSeatIndices.toList(),
          absentIndices: _absentSeatIndices.toList(),
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
            slotId: widget.slotId,
            courseCode: widget.courseCode,
            presentCount: _presentSeatIndices.length,
            totalCapacity: widget.capacity,
            students: _students.map((s) => StudentInfo(
              rollNumber: s.rollNumber,
              name: s.name,
              email: s.studentId,
              sectionId: '',
              classId: '',
            )).toList(),
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

  void _handlePhysicalTapEnd() {
    if (!_isAttendanceSubmitted) {
      _showSubmitFirstDialog();
      return;
    }
    _showEndSessionConfirmation();
  }

  void _showSubmitFirstDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_rounded,
                      color: AppColors.warningAmber, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  'SUBMIT ATTENDANCE FIRST',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Attendance has been saved locally but not yet submitted.\n\nPlease submit before ending the session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('CANCEL',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _handleSubmitAttendance();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('SUBMIT NOW',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEndSessionConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.successLime.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.checklist_rounded,
                      color: AppColors.successLime, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  'END SESSION',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$_presentCount students marked present.\nEnd "${widget.courseName}"?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('CANCEL',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _handleEndAttendance();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('END SESSION',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dismissStudentInfo();
    _cellPulseController?.dispose();
    _killSwitchJTimer?.cancel();
    _killSwitchFocusNode.dispose();
    _endSessionCooldownTimer?.cancel();
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
          students: _students.map((s) => StudentInfo(
            rollNumber: s.rollNumber,
            name: s.name,
            email: s.studentId,
            sectionId: '',
            classId: '',
          )).toList(),
          presentIndices: _presentSeatIndices.toList(),
          absentIndices: _absentSeatIndices.toList(),
          isAttendanceSubmitted: _isAttendanceSubmitted,
        ),
      ),
    );
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
                          ? AbsorbPointer(
                              absorbing: _isAttendanceSubmitted,
                              child: _buildInteractionGrid(isDark),
                            )
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
          if (widget.onNavigateBack != null)
            IconButton(
              onPressed: widget.onNavigateBack,
              icon: Icon(Icons.arrow_back_rounded,
                  color: isDark ? Colors.white70 : Colors.black54),
              tooltip: 'Back to Idle',
            ),
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

    const cols = _gridColumns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth - 80;
        const dotArea = 32.0;
        final gridArea = availableW - dotArea;
        final cellGap = 8.0;
        final cellSize = ((gridArea - (cols - 1) * cellGap) / cols).clamp(40.0, 72.0);
        final gridW = cols * cellSize + (cols - 1) * cellGap;
        final rows = (itemCount / cols).ceil();

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: Center(
            child: SizedBox(
              width: dotArea + gridW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int row = 0; row < rows; row++) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final start = row * cols;
                            final end = (start + cols > itemCount) ? itemCount : start + cols;
                            for (int i = start; i < end; i++) {
                              _presentSeatIndices.add(i);
                              _absentSeatIndices.remove(i);
                            }
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: gridW,
                          child: Wrap(
                            spacing: cellGap,
                            runSpacing: cellGap,
                            children: List.generate(cols, (col) {
                              final index = row * cols + col;
                              if (index >= itemCount) {
                                return SizedBox(
                                  width: cellSize, height: cellSize,
                                );
                              }
                              return _buildKeycapCell(index, isDark, cellSize);
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (row < rows - 1) SizedBox(height: cellGap),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeycapCell(int index, bool isDark, double size) {
    final isPresent = _presentSeatIndices.contains(index);
    final isAbsent = _absentSeatIndices.contains(index);
    final student = index < _students.length ? _students[index] : null;
    final roll = RollNumberUtils.formatDisplay(student?.rollNumber ?? RollNumberUtils.generateSeatCode(index));

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isPresent) {
      bgColor = AppColors.successLime;
      borderColor = AppColors.successLime;
      textColor = Colors.white;
    } else if (isAbsent) {
      bgColor = AppColors.error;
      borderColor = AppColors.error;
      textColor = Colors.white;
    } else {
      bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
      borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
      textColor = isDark ? Colors.white70 : const Color(0xFF475569);
    }

    return Builder(
      builder: (cellContext) {
        return GestureDetector(
          onTapDown: (_) => _handleCellTapDown(index),
          onLongPressStart: (_) => _showStudentInfo(index, cellContext),
          onLongPressEnd: (_) => _dismissStudentInfo(),
          child: AnimatedBuilder(
            animation: _cellPulseAnimation!,
            builder: (context, child) {
              final scale = _cellPulseAnimation?.value ?? 1.0;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borderColor,
                  width: isPresent || isAbsent ? 1.5 : 1.0,
                ),
                boxShadow: isPresent || isAbsent
                    ? [BoxShadow(color: bgColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Center(
                child: Text(
                  roll,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
                    final roll = RollNumberUtils.formatDisplay(
                        student?.rollNumber ??
                        RollNumberUtils.generateSeatCode(index));
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
                              width: 36, height: 28,
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
    final hasMarked = presentLocal > 0 || absentCount > 0;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
        border: Border(
            top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _buildFooterBadge('PRESENT', AppColors.successLime, '$presentLocal'),
          const SizedBox(width: 16),
          _buildFooterBadge('ABSENT', AppColors.error, '$absentCount'),
          if (unmarkedCount > 0) ...[
            const SizedBox(width: 16),
            _buildFooterBadge('UNMARKED', isDark ? Colors.white38 : const Color(0xFF94A3B8), '$unmarkedCount'),
          ],
          const Spacer(),
          if (_stage == _Stage.grid)
            ElevatedButton.icon(
              onPressed: hasMarked ? _handleSaveAttendance : null,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('SAVE',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                disabledForegroundColor: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                minimumSize: const Size(140, 48),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          if (_stage == _Stage.splitReview) ...[
            OutlinedButton.icon(
              onPressed: () => setState(() => _stage = _Stage.grid),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('BACK',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                side: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                minimumSize: const Size(120, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmitAttendance,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(_isSubmitting ? 'SUBMITTING...' : 'SUBMIT',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                disabledForegroundColor: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                minimumSize: const Size(160, 48),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterBadge(String label, Color color, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: color)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color)),
        ],
      ),
    );
  }
}

class _StudentInfoBubble extends StatefulWidget {
  final String studentName;
  final String rollDisplay;
  final Offset cellPosition;
  final Size cellSize;

  const _StudentInfoBubble({
    required this.studentName,
    required this.rollDisplay,
    required this.cellPosition,
    required this.cellSize,
  });

  @override
  State<_StudentInfoBubble> createState() => _StudentInfoBubbleState();
}

class _StudentInfoBubbleState extends State<_StudentInfoBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    const bubbleW = 280.0;
    const coneH = 12.0;
    const avatarSize = 40.0;

    double left = widget.cellPosition.dx + widget.cellSize.width / 2 - bubbleW / 2;
    left = left.clamp(12.0, screenW - bubbleW - 12.0);
    final top = widget.cellPosition.dy - coneH - 8.0;

    return Positioned(
      left: left,
      top: top,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: bubbleW,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 22,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.studentName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.rollDisplay,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentEntry {
  final String studentId;
  final String name;
  final String rollNumber;

  const _StudentEntry({
    required this.studentId,
    required this.name,
    required this.rollNumber,
  });
}
