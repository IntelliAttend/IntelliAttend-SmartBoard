import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../main.dart' show kPreviewWorkspace;
import '../../models/board_notification.dart';
import '../../models/course_topic.dart';
import '../../models/syllabus_unit.dart';
import '../../services/api_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/notification_listener_service.dart';
import '../../services/resource_service.dart';
import '../../services/syllabus_service.dart';
import '../../services/document_service.dart';
import 'summary_screen.dart';
import 'document_viewer_screen.dart';
import 'file_viewer_screen.dart';
import 'attendance_screen.dart';
import '../../services/time_sync_service.dart';
import '../../services/websocket_service.dart';
import '../../services/student_service.dart';
import '../../services/sync_manager.dart';


enum _WorkspaceTab { resources, topics, calendar }

enum _ResourceFilter { myResources, collegeResources }

class _TimelineEvent {
  final String time;
  final String title;
  final String description;

  const _TimelineEvent({
    required this.time,
    required this.title,
    required this.description,
  });
}

class _FlashbackDay {
  final String label;
  final String date;
  final List<_TimelineEvent> events;

  const _FlashbackDay({
    required this.label,
    required this.date,
    required this.events,
  });
}


class _WSColors {
  final Color bg;
  final Color surface;
  final Color elevated;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  _WSColors({
    required this.bg,
    required this.surface,
    required this.elevated,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  factory _WSColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _WSColors(
      bg: isDark ? AppColors.bgDark : AppColors.bgLight,
      surface: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
      elevated: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF1F5F9),
      border: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
      borderStrong: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
      textPrimary: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
      textSecondary: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
      textMuted: isDark ? Colors.white38 : Colors.grey,
    );
  }
}

class WorkspaceScreen extends StatefulWidget {
  final String sessionId;
  final String courseName;
  final String facultyName;
  final String roomName;
  final String? sectionId;
  final String? slotId;
  final String? courseCode;
  final int presentCount;
  final int totalCapacity;
  final List<StudentInfo>? students;
  final List<int>? presentIndices;
  final List<int>? absentIndices;
  final bool isAttendanceSubmitted;
  final WebsocketService? websocketService;

  const WorkspaceScreen({
    super.key,
    required this.sessionId,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    this.sectionId,
    this.slotId,
    this.courseCode,
    required this.presentCount,
    required this.totalCapacity,
    this.students,
    this.presentIndices,
    this.absentIndices,
    this.isAttendanceSubmitted = false,
    this.websocketService,
  });

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with TickerProviderStateMixin {
  _WorkspaceTab _activeTab = _WorkspaceTab.resources;
  bool _isEnding = false;
  late TabController _resourceTabController;




  List<BoardNotification> _resources = [];
  List<BoardNotification> _collegeResources = [];
  bool _resourcesLoaded = false;
  BoardNotification? _selectedResource;
  StreamSubscription<List<BoardNotification>>? _resourcesSub;

  // ── Topics / Syllabus state ──
  List<SyllabusUnit> _syllabusUnits = [];
  List<CourseTopic> _allTopics = [];
  bool _topicsLoaded = false;
  int _topicFilter = 0;
  String _topicSearchQuery = '';
  final TextEditingController _topicSearchController = TextEditingController();
  final List<bool> _expandedUnits = [];
  static const _topicFilterLabels = ['All', 'Completed', 'In Progress', 'Pending'];

  late AnimationController _pulseController;
  _WSColors get _palette => _WSColors.of(context);

  // Brand / accent colors (theme-independent)
  static const Color _teal = AppColors.primaryTeal;
  static Color get _tealAlpha => _teal.withValues(alpha: 0.2);
  static Color get _tealLight => _teal.withValues(alpha: 0.12);
  static Color get _green => AppColors.successLime;
  static Color get _greenLight => AppColors.successLime.withValues(alpha: 0.12);
  static Color get _red => AppColors.error;
  static Color get _amber => AppColors.warningAmber;
  static Color get _purple => const Color(0xFFA78BFA);

  // ── Pending sync state ──
  int _pendingSyncCount = 0;

  List<_TimelineEvent> _todayTimeline = [];
  List<_FlashbackDay> _flashbackDays = [];
  Map<String, Map<String, dynamic>> _calendarEvents = {};
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _resourceTabController = TabController(length: 2, vsync: this);
    _resourceTabController.addListener(() {
      if (!_resourceTabController.indexIsChanging) setState(() {});
    });

    if (kPreviewWorkspace) {
      _resourcesLoaded = true;
      _historyLoaded = true;
    } else {
      _loadResources();
      _loadSessionHistory();
      _resourcesSub = NotificationListenerService().notificationsStream.listen((notifications) {
        if (!mounted) return;
        setState(() {
          _resources = notifications.where((n) => n.hasAttachment).toList();
          _resourcesLoaded = true;
          if (_selectedResource != null &&
              !_resources.any((resource) => resource.id == _selectedResource!.id)) {
            _selectedResource = null;
          }
          if (_selectedResource == null && _resources.isNotEmpty) {
            _selectedResource = _resources.first;
          }
        });
      });
    }
    _loadTopics();

    // Subscribe to background attendance sync for UI feedback
    SyncManager().onAttendanceSynced = _onAttendanceSynced;
    SyncManager().onAttendanceDropped = _onAttendanceDropped;
    SyncManager().onPendingCountChanged = _onPendingCountChanged;

    // Check initial pending count
    SyncManager().getPendingCount().then((count) {
      if (mounted) setState(() => _pendingSyncCount = count);
    });
  }

  void _onAttendanceSynced(String sessionId) {
    if (!mounted) return;
    if (sessionId != widget.sessionId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Attendance synced to server',
            style: TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: AppColors.successLime,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onAttendanceDropped(String sessionId, String reason) {
    if (!mounted) return;
    if (sessionId != widget.sessionId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Attendance sync failed: $reason',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _onPendingCountChanged(int count) {
    if (!mounted) return;
    setState(() => _pendingSyncCount = count);
  }

  Future<void> _loadTopics() async {
    final code = widget.courseCode;
    final section = widget.sectionId;
    if (code == null || code.isEmpty || section == null || section.isEmpty) {
      if (mounted) setState(() => _topicsLoaded = true);
      return;
    }

    try {
      final results = await Future.wait([
        SyllabusService.getUnitsWithProgress(code, section),
        SyllabusService.getTopics(code, section),
      ]);
      if (!mounted) return;

      final units = results[0] as List<SyllabusUnit>;
      final topics = results[1] as List<CourseTopic>;

      setState(() {
        _syllabusUnits = units;
        _allTopics = topics;
        _topicsLoaded = true;
        _expandedUnits.clear();
        _expandedUnits.addAll(List.filled(units.length, false));
        if (units.isNotEmpty) _expandedUnits[0] = true;
      });
    } catch (e) {
      Log.w('[Workspace] Topics load failed: $e');
      if (mounted) setState(() => _topicsLoaded = true);
    }
  }

  Future<void> _loadSessionHistory() async {
    try {
      final data = await ApiService.getBoardSessionHistory(daysBack: 7);
      if (!mounted) return;

      final todayRaw = data['today_sessions'] as List<dynamic>? ?? [];
      final pastRaw = data['past_sessions'] as List<dynamic>? ?? [];
      final calRaw = data['calendar_events'] as List<dynamic>? ?? [];

      final todayEvents = todayRaw.map((s) => _TimelineEvent(
        time: (s['start_time'] as String? ?? '').isNotEmpty
            ? '${s['start_time']} – ${s['end_time'] ?? ''}'
            : '',
        title: s['course_name'] as String? ?? '',
        description: _buildSessionDescription(s),
      )).toList();

      final flashback = <_FlashbackDay>[];
      for (final day in pastRaw) {
        final sessions = (day['sessions'] as List<dynamic>? ?? []);
        flashback.add(_FlashbackDay(
          label: day['day_label'] as String? ?? '',
          date: day['date'] as String? ?? '',
          events: sessions.map((s) => _TimelineEvent(
            time: (s['start_time'] as String? ?? '').isNotEmpty
                ? '${s['start_time']} – ${s['end_time'] ?? ''}'
                : '',
            title: s['course_name'] as String? ?? '',
            description: _buildSessionDescription(s),
          )).toList(),
        ));
      }

      final calMap = <String, Map<String, dynamic>>{};
      for (final ev in calRaw) {
        calMap[ev['date'] as String] = Map<String, dynamic>.from(ev);
      }

      setState(() {
        _todayTimeline = todayEvents;
        _flashbackDays = flashback;
        _calendarEvents = calMap;
        _historyLoaded = true;
      });
    } catch (e) {
      Log.w('[Workspace] Session history load failed: $e');
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  String _buildSessionDescription(Map<String, dynamic> session) {
    final parts = <String>[];
    final faculty = session['faculty_name'] as String? ?? '';
    if (faculty.isNotEmpty) parts.add(faculty);
    final section = session['section_id'] as String? ?? '';
    if (section.isNotEmpty) parts.add('Section $section');
    final present = session['attendance_count'] as int? ?? 0;
    final total = session['total_students'] as int? ?? 0;
    if (total > 0) parts.add('Attendance: $present/$total');
    return parts.join(' · ');
  }

  Future<void> _loadResources() async {
    final results = await Future.wait([
      ResourceService.getMyResources(
        sessionId: widget.sessionId,
        sectionId: widget.sectionId,
        courseName: widget.courseName,
      ),
      ResourceService.getCollegeResources(
        courseName: widget.courseName,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _resources = results[0];
      _collegeResources = results[1];
      _resourcesLoaded = true;
      if (_selectedResource == null && _resources.isNotEmpty) {
        _selectedResource = _resources.first;
      }
    });
  }

  @override
  void dispose() {
    _resourcesSub?.cancel();
    _resourceTabController.dispose();
    _pulseController.dispose();
    _topicSearchController.dispose();
    // Unsubscribe from sync callbacks
    if (SyncManager().onAttendanceSynced == _onAttendanceSynced) {
      SyncManager().onAttendanceSynced = null;
    }
    if (SyncManager().onAttendanceDropped == _onAttendanceDropped) {
      SyncManager().onAttendanceDropped = null;
    }
    if (SyncManager().onPendingCountChanged == _onPendingCountChanged) {
      SyncManager().onPendingCountChanged = null;
    }
    super.dispose();
  }



  bool _isPdf(String name) => name.split('.').last.toLowerCase() == 'pdf';

  Future<void> _openFile(BoardNotification notification) async {
    if (!mounted) return;
    final url = notification.attachmentUrl;
    final fileName = notification.displayAttachmentName;
    if (url == null || url.isEmpty) return;

    // Download from R2 (or any URL) via DocumentService
    final localPath = await DocumentService().downloadDocument(url, fileName);
    if (!mounted) return;

    if (localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load $fileName', style: TextStyle(fontWeight: FontWeight.w500)),
          backgroundColor: _teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isPdf(fileName)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(filePath: localPath, fileName: fileName),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FileViewerScreen(filePath: localPath, fileName: fileName),
      ));
    }
  }

  Future<void> _handleEndSession() async {
    if (_isEnding) return;

    if (!widget.isAttendanceSubmitted) {
      final goBack = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
              child: Container(
              width: 420,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.warningAmber.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_upload_rounded,
                        color: AppColors.warningAmber, size: 28),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ATTENDANCE NOT SUBMITTED',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Attendance has been saved locally but not yet submitted to the server.\n\nPlease go back and submit before ending the session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _palette.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('CANCEL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _palette.textMuted)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('GO BACK & SUBMIT',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
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
      if (goBack == true && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final rate = widget.totalCapacity > 0
            ? (widget.presentCount / widget.totalCapacity * 100).toInt()
            : 0;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.successLime.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.checklist_rounded,
                        color: AppColors.successLime, size: 28),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ATTENDANCE SUBMITTED ✓',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.courseName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCardStat('Present', '${widget.presentCount}', AppColors.successLime),
                      const SizedBox(width: 32),
                      _buildCardStat('Total', '${widget.totalCapacity}', _palette.textSecondary),
                      const SizedBox(width: 32),
                      _buildCardStat('Rate', '$rate%', AppColors.primaryTeal),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('CANCEL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _palette.textMuted)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.successLime,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('END SESSION',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result != true || !mounted) return;
    setState(() => _isEnding = true);
    try {
      await ApiService.terminateSession(widget.sessionId);
    } catch (e) {
      Log.e('[Workspace] Error ending session: $e');
      HeartbeatService.enqueuePendingTermination(widget.sessionId);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SummaryScreen(
        sessionId: widget.sessionId,
        presentCount: widget.presentCount,
        totalCapacity: widget.totalCapacity,
        courseName: widget.courseName,
        facultyName: widget.facultyName,
        slotId: widget.slotId,
        students: widget.students,
        presentIndices: widget.presentIndices,
        absentIndices: widget.absentIndices,
        isAttendanceSubmitted: widget.isAttendanceSubmitted,
      ),
    ));
  }

  static Widget _buildCardStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _palette.bg,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _activeTab == _WorkspaceTab.resources
                        ? _buildResourcesView()
                        : _activeTab == _WorkspaceTab.topics
                            ? _buildTopicsView()
                            : _buildCalendarView(),
                  ),
                ),
                Container(width: 1, color: _palette.border),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SizedBox(width: 400, child: _buildLectureHistory()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TOP BAR — dark glass header matching idle_screen dark mode
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    final now = TimeSyncService.timeNow;
    final dateStr = '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: _palette.bg,
        border: Border(bottom: BorderSide(color: _palette.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left group: back arrow + session info
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _palette.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _palette.border),
                      ),
                      child: Icon(Icons.arrow_back_rounded, color: _palette.textSecondary, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Container(width: 1, height: 28, color: _palette.border),
                const SizedBox(width: 20),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'CURRENT SESSION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: _palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.courseName}${widget.sectionId != null ? "  ·  ${widget.sectionId!.toUpperCase()}" : ""}  ·  ${widget.facultyName}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _palette.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pending sync indicator + Date + Time
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingSyncCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.warningAmber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_pendingSyncCount pending',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warningAmber,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.calendar_today_rounded, size: 14, color: _teal),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _palette.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 16, color: _palette.border),
              const SizedBox(width: 12),
              Icon(Icons.schedule_rounded, size: 14, color: _teal),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _palette.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _weekday(int w) {
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d[w - 1];
  }

  String _month(int m) {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return mo[m - 1];
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SIDEBAR — dark glass with teal active state
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: _palette.bg,
        border: Border(right: BorderSide(color: _palette.border, width: 1.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Faculty / Profile card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _palette.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _tealLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _tealAlpha, width: 1.5),
                    ),
                    child: Icon(Icons.person_rounded, size: 24, color: _teal),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lecture Workspace',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.facultyName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _teal,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Nav items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _sidebarItem(icon: Icons.folder_open_rounded, label: 'Resources', tab: _WorkspaceTab.resources, subtitle: 'Files & materials'),
                const SizedBox(height: 4),
                _sidebarItem(icon: Icons.menu_book_rounded, label: 'Topics', tab: _WorkspaceTab.topics, subtitle: 'Syllabus & progress'),
                const SizedBox(height: 4),
                _sidebarItem(icon: Icons.calendar_month_rounded, label: 'Calendar', tab: _WorkspaceTab.calendar, subtitle: 'Sessions & events'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Attendance — navigates back to attendance screen
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => AttendanceScreen(
                        sessionId: widget.sessionId,
                        capacity: widget.totalCapacity,
                        courseName: widget.courseName,
                        facultyName: widget.facultyName,
                        roomName: widget.roomName,
                        slotId: widget.slotId,
                        courseCode: widget.courseCode,
                        initialPresentCount: widget.presentCount,
                        previousPresentIndices: widget.presentIndices,
                        previousAbsentIndices: widget.absentIndices,
                        boardId: '',
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _palette.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _palette.elevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people_rounded, size: 20, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attendance',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: _palette.textPrimary,
                              ),
                            ),
                            Text(
                              'Mark & manage',
                              style: TextStyle(fontSize: 10, color: _palette.textMuted),
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

          const Spacer(),
          // End session button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isEnding ? null : _handleEndSession,
                icon: _isEnding
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  _isEnding ? 'Ending…' : 'End Session',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _palette.textMuted,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String label,
    required _WorkspaceTab tab,
    String? subtitle,
  }) {
    final isActive = _activeTab == tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? _teal : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? _teal : _palette.border,
              width: isActive ? 0 : 1,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: _teal.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.15) : _palette.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: isActive ? Colors.white : _palette.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? Colors.white : _palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive ? Colors.white.withValues(alpha: 0.6) : _palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // RESOURCES VIEW
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildResourcesView() {
    return Column(
      key: const ValueKey('resources'),
      children: [
        // TabBar — animated underline indicator (matching timetable)
        Container(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _palette.border)),
            ),
            child: TabBar(
              controller: _resourceTabController,
              indicatorColor: _teal,
              indicatorWeight: 3,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 8),
              labelColor: _teal,
              unselectedLabelColor: _palette.textMuted,
              labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_rounded, size: 18),
                      const SizedBox(width: 8),
                      const Text('My Resources'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_rounded, size: 18),
                      const SizedBox(width: 8),
                      const Text('College Resources'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            controller: _resourceTabController,
            children: [
              _buildAssetList(_resources, _ResourceFilter.myResources),
              _buildAssetList(_collegeResources, _ResourceFilter.collegeResources),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssetList(List<BoardNotification> items, _ResourceFilter filter) {
    if (!_resourcesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEmptyResourceHero(filter),
          const SizedBox(height: 12),
          _buildPreviewRailCard(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Lecture Notes',
            subtitle: 'PDF packs, handouts, and course references',
            accentColor: _teal,
          ),
          const SizedBox(height: 10),
          _buildPreviewRailCard(
            icon: Icons.slideshow_rounded,
            title: 'Board Snapshot',
            subtitle: 'Whiteboard captures and projection exports',
            accentColor: _purple,
          ),
          const SizedBox(height: 10),
          _buildPreviewRailCard(
            icon: Icons.table_chart_rounded,
            title: 'Attendance Export',
            subtitle: 'Summary sheets and session analytics',
            accentColor: _green,
          ),
          if (filter == _ResourceFilter.collegeResources) ...[
            const SizedBox(height: 10),
            _buildPreviewRailCard(
              icon: Icons.library_books_rounded,
              title: 'Department Library',
              subtitle: 'Curated academic resources from the college repository',
              accentColor: _amber,
            ),
            const SizedBox(height: 10),
            _buildPreviewRailCard(
              icon: Icons.video_library_rounded,
              title: 'Lecture Recordings',
              subtitle: 'Archived video sessions from previous lectures',
              accentColor: _purple,
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildResourceCard(items[index]),
      ),
    );
  }

  Widget _buildResourceCard(BoardNotification notification) {
    final ext = notification.displayAttachmentName.split('.').last.toLowerCase();
    final isSelected = _selectedResource == notification;
    final name = notification.displayAttachmentName;
    final displayName = name.length > 22 ? '${name.substring(0, 20)}…' : name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedResource = notification),
        onDoubleTap: () => _openFile(notification),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? _tealLight : _palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _teal : _palette.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _fileIcon(ext),
                size: 32,
                color: isSelected ? _teal : _palette.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _palette.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Removed _buildViewerPane — file list only, no preview.

  Widget _buildEmptyResourceHero(_ResourceFilter filter) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _palette.borderStrong),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _tealLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _tealAlpha),
            ),
            child: Icon(Icons.folder_open_rounded, color: _teal, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filter == _ResourceFilter.myResources ? 'My Resources' : 'College Resources',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  filter == _ResourceFilter.myResources
                      ? 'Live cards appear here once the notification cache is populated.'
                      : 'Departmental library card wall is reserved for curated assets.',
                  style: TextStyle(fontSize: 12, color: _palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRailCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: accentColor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: _palette.textMuted, height: 1.35),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _palette.textMuted.withValues(alpha: 0.55)),
        ],
      ),
    );
  }

  // Removed _buildResourcePreview — file list only, no preview.

  // ══════════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL — Unified Lecture History (today + past days, scrollable)
  // ══════════════════════════════════════════════════════════════════════════════

  List<_FlashbackDay> get _allLectureDays => [
        ..._flashbackDays.reversed,
        _FlashbackDay(
          label: 'Today',
          date: _todayDate,
          events: _todayTimeline,
        ),
      ];

  String get _todayDate {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Widget _buildLectureHistory() {
    final days = _allLectureDays.where((d) => d.events.isNotEmpty).toList();
    final hasData = days.isNotEmpty;
    return Container(
      color: _palette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _tealLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _tealAlpha),
                  ),
                  child: Icon(Icons.history_rounded, size: 18, color: _teal),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lecture History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _palette.textPrimary,
                      ),
                    ),
                    Text(
                      !_historyLoaded
                          ? 'Loading session history…'
                          : hasData
                              ? 'Scroll up for older sessions'
                              : 'No session history yet',
                      style: TextStyle(fontSize: 11, color: _palette.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Timeline — up to 60% of available height
          Expanded(
            child: hasData
                ? LayoutBuilder(
                    builder: (context, constraints) => ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        itemCount: days.length,
                        itemBuilder: (context, dayIndex) {
                      final day = days[dayIndex];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Day section header
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: day.label == 'Today' ? _tealLight : _palette.elevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    day.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: day.label == 'Today' ? _teal : _palette.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  day.date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Events for this day
                          ...day.events.map((event) => _buildTimelineItem(event)),
                          // Divider between days
                          if (dayIndex < days.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Container(height: 1, color: _palette.border),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off_rounded,
                            size: 48, color: _palette.textMuted.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('Session timeline will appear here',
                            style: TextStyle(fontSize: 13, color: _palette.textMuted)),
                      ],
                    ),
                  ),
          ),

          // Open SmartBoard button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            decoration: BoxDecoration(
              color: _palette.bg,
              border: Border(top: BorderSide(color: _palette.border)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.display_settings_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Text('Opening SmartBoard projection…',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      backgroundColor: _teal,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.display_settings_rounded, size: 20),
                label: Text(
                  'Open SmartBoard',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: _teal.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineEvent event) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot — larger
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: _palette.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: _palette.borderStrong,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _palette.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: _palette.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        event.time,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _palette.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    event.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: _palette.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TOPICS VIEW — Syllabus units & subtopics with progress
  // ══════════════════════════════════════════════════════════════════════════════

  int get _totalTopicCount => _allTopics.length;
  int get _completedTopicCount => _allTopics.where((t) => t.isCompleted).length;

  List<CourseTopic> get _filteredTopics {
    var topics = _allTopics.toList();
    if (_topicSearchQuery.isNotEmpty) {
      final q = _topicSearchQuery.toLowerCase();
      topics = topics.where((t) => t.name.toLowerCase().contains(q)).toList();
    }
    switch (_topicFilter) {
      case 1:
        topics = topics.where((t) => t.isCompleted).toList();
        break;
      case 2:
        topics = topics.where((t) => !t.isCompleted).toList();
        break;
      case 3:
        topics = topics.where((t) => !t.isCompleted).toList();
        break;
    }
    return topics;
  }

  Widget _buildTopicsView() {
    return Column(
      key: const ValueKey('topics'),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _palette.border),
                ),
                child: TextField(
                  controller: _topicSearchController,
                  readOnly: true,
                  onChanged: (val) => setState(() => _topicSearchQuery = val),
                  style: TextStyle(fontSize: 14, color: _palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search topics...',
                    hintStyle: TextStyle(color: _palette.textMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: _palette.textMuted, size: 20),
                    suffixIcon: _topicSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: _palette.textMuted, size: 18),
                            onPressed: () {
                              _topicSearchController.clear();
                              setState(() => _topicSearchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ...List.generate(_topicFilterLabels.length, (i) {
                    final isActive = _topicFilter == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _topicFilter = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isActive ? _teal.withValues(alpha: 0.15) : _palette.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive ? _teal.withValues(alpha: 0.3) : _palette.border,
                            ),
                          ),
                          child: Text(
                            _topicFilterLabels[i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? _teal : _palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  if (_totalTopicCount > 0)
                    Text(
                      '$_completedTopicCount / $_totalTopicCount topics',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _topicSearchQuery.isNotEmpty || _topicFilter != 0
              ? _buildFilteredTopicsList()
              : _buildUnitList(),
        ),
      ],
    );
  }

  Widget _buildFilteredTopicsList() {
    final filtered = _filteredTopics;
    if (!_topicsLoaded) return const Center(child: CircularProgressIndicator());
    if (filtered.isEmpty) return _buildTopicsEmptyState('No topics match your filter');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildTopicItem(filtered[index], index, filtered.length),
    );
  }

  Widget _buildUnitList() {
    if (!_topicsLoaded) return const Center(child: CircularProgressIndicator());
    if (_syllabusUnits.isEmpty) return _buildTopicsEmptyState('Syllabus topics have not been added yet');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _syllabusUnits.length,
      itemBuilder: (context, index) => _buildUnitTile(_syllabusUnits[index], index),
    );
  }

  Widget _buildUnitTile(SyllabusUnit unit, int unitIndex) {
    final isExpanded = _expandedUnits.length > unitIndex ? _expandedUnits[unitIndex] : false;
    final allDone = unit.isComplete;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? _teal.withValues(alpha: 0.25) : _palette.border,
          width: isExpanded ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (val) {
            HapticFeedback.lightImpact();
            setState(() {
              while (_expandedUnits.length <= unitIndex) {
                _expandedUnits.add(false);
              }
              _expandedUnits[unitIndex] = val;
            });
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: allDone
                  ? AppColors.successLime.withValues(alpha: 0.15)
                  : _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: allDone
                  ? const Icon(Icons.check_rounded, size: 20, color: AppColors.successLime)
                  : Text(
                      '${unit.unitNumber}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _teal),
                    ),
            ),
          ),
          title: Text(
            unit.title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _palette.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(
                  '${unit.completedTopics} / ${unit.totalTopics} Topics',
                  style: TextStyle(fontSize: 11, color: _palette.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 60,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: unit.totalTopics > 0 ? unit.completedTopics / unit.totalTopics : 0,
                      backgroundColor: _palette.textMuted.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(allDone ? AppColors.successLime : _teal),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${unit.percentage.round()}%',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _palette.textSecondary),
                ),
              ],
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
            color: _palette.textMuted,
            size: 22,
          ),
          children: _allTopics
              .where((t) => t.unitNumber == unit.unitNumber)
              .toList()
              .asMap()
              .entries
              .map((entry) => _buildTopicItem(entry.value, entry.key, unit.topics.length))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildTopicItem(CourseTopic topic, int index, int total) {
    final bool isLast = index == total - 1;
    final bool isCompleted = topic.isCompleted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.successLime
                        : _palette.textMuted.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted ? Icons.check : Icons.circle,
                    size: isCompleted ? 12 : 6,
                    color: isCompleted ? Colors.white : _palette.textMuted.withValues(alpha: 0.4),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 20,
                    color: isCompleted
                        ? AppColors.successLime.withValues(alpha: 0.3)
                        : _palette.textMuted.withValues(alpha: 0.1),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCompleted ? FontWeight.w600 : FontWeight.w500,
                          color: isCompleted
                              ? _palette.textPrimary
                              : _palette.textSecondary.withValues(alpha: 0.6),
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          decorationColor: _palette.textMuted.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    if (isCompleted)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.successLime.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Completed',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.successLime),
                        ),
                      ),
                  ],
                ),
                if (!isLast && _topicSearchQuery.isEmpty && _topicFilter == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(height: 0.5, color: _palette.border),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 56, color: _palette.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _palette.textSecondary),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CALENDAR VIEW
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildCalendarView() {
    final now = TimeSyncService.timeNow;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final firstWeekday = DateTime(now.year, now.month, 1).weekday;
    return Padding(
      key: const ValueKey('calendar'),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _tealLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _tealAlpha),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 22, color: _teal),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_month(now.month)} ${now.year}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _palette.textPrimary,
                    ),
                  ),
                  Text(
                    'Upcoming lectures & events',
                    style: TextStyle(fontSize: 12, color: _palette.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Weekday headers
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.3,
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) =>
              Center(
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _palette.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ).toList(),
          ),
          const SizedBox(height: 6),
          // Day cells
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.1,
              ),
              itemCount: firstWeekday - 1 + daysInMonth,
              itemBuilder: (context, index) {
                final day = index - (firstWeekday - 2);
                if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
                final isToday = day == now.day;
                final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final calEvent = _calendarEvents[dateKey];
                final hasSessions = calEvent != null && (calEvent['session_count'] as int? ?? 0) > 0;
                return GestureDetector(
                  onTap: hasSessions ? () => _showCalendarDaySessions(dateKey, calEvent) : null,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isToday ? _teal : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: hasSessions && !isToday
                          ? Border.all(color: _teal.withValues(alpha: 0.4), width: 1)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isToday ? Colors.white : _palette.textSecondary,
                          ),
                        ),
                        if (hasSessions) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              (calEvent['session_count'] as int? ?? 0).clamp(0, 4),
                              (_) => Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: isToday ? Colors.white70 : _teal,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCalendarDaySessions(String dateKey, Map<String, dynamic> calEvent) {
    final now = TimeSyncService.timeNow;
    final dateParts = dateKey.split('-');
    final month = int.tryParse(dateParts[1]) ?? now.month;
    final day = int.tryParse(dateParts[2]) ?? now.day;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateLabel = '${months[month - 1]} $day';
    final sessionCount = calEvent['session_count'] as int? ?? 0;
    final hasCompleted = calEvent['has_completed'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.45,
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: _palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _palette.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: _teal),
                  const SizedBox(width: 10),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _palette.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasCompleted ? _greenLight : _palette.elevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$sessionCount session${sessionCount != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasCompleted ? _green : _palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Session details will appear here',
                  style: TextStyle(fontSize: 13, color: _palette.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════════

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'html':
        return Icons.language_rounded;
      case 'md':
      case 'txt':
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
