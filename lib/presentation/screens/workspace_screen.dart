import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../models/board_notification.dart';
import '../../services/api_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/notification_listener_service.dart';
import '../../services/resource_service.dart';
import '../../services/document_service.dart';
import 'summary_screen.dart';
import 'document_viewer_screen.dart';
import 'file_viewer_screen.dart';
import 'attendance_screen.dart';
import '../../services/time_sync_service.dart';
import '../../services/websocket_service.dart';
import '../../services/student_service.dart';
import '../../core/config/app_config.dart';


enum _WorkspaceTab { resources, calendar, settings }

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
  final int presentCount;
  final int totalCapacity;
  final List<StudentInfo>? students;
  final List<int>? presentIndices;
  final List<int>? absentIndices;
  final bool isAttendanceSubmitted;

  const WorkspaceScreen({
    super.key,
    required this.sessionId,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    this.sectionId,
    this.slotId,
    required this.presentCount,
    required this.totalCapacity,
    this.students,
    this.presentIndices,
    this.absentIndices,
    this.isAttendanceSubmitted = false,
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
  static Color get _amberLight => AppColors.warningAmber.withValues(alpha: 0.12);
  static Color get _purple => const Color(0xFFA78BFA);


  List<_TimelineEvent> get _todayTimeline => [];

  static const List<_FlashbackDay> _flashbackDays = [];

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
    _loadResources();
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
                        : _activeTab == _WorkspaceTab.calendar
                            ? _buildCalendarView()
                            : _buildSettingsView(),
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
                    onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
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
          // Date + Time — flush to far right edge, no box
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                _sidebarItem(icon: Icons.calendar_month_rounded, label: 'Calendar', tab: _WorkspaceTab.calendar, subtitle: 'Sessions & events'),
                const SizedBox(height: 4),
                _sidebarItem(icon: Icons.settings_outlined, label: 'Settings', tab: _WorkspaceTab.settings, subtitle: 'Preferences'),
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AttendanceScreen(
                        sessionId: widget.sessionId,
                        websocketService: WebsocketService(AppConfig.baseUrl),
                        capacity: widget.totalCapacity,
                        courseName: widget.courseName,
                        facultyName: widget.facultyName,
                        roomName: widget.roomName,
                        sectionId: widget.sectionId,
                        slotId: widget.slotId,
                        initialPresentCount: widget.presentCount,
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
                      hasData ? 'Scroll up for older sessions' : 'No session history yet',
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

  Widget _sectionHeader(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: _tealLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _tealAlpha),
          ),
          child: Icon(icon, size: 18, color: _teal),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _palette.textPrimary)),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: _palette.textMuted)),
          ],
        ),
      ],
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
                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday ? _teal : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                        color: isToday ? Colors.white : _palette.textSecondary,
                      ),
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

  // ══════════════════════════════════════════════════════════════════════════════
  // SETTINGS VIEW
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(Icons.tune_rounded, 'Display Settings', 'UI preferences'),
                const SizedBox(height: 20),
                _settingsTile(
                  icon: Icons.brightness_6_rounded,
                  iconBg: _amberLight,
                  iconColor: _amber,
                  title: 'Theme',
                  subtitle: 'Toggle between light and dark mode',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'light', label: Text('Light')),
                      ButtonSegment(value: 'dark', label: Text('Dark')),
                    ],
                    selected: const {'dark'},
                    onSelectionChanged: (_) {},
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: _teal,
                      selectedForegroundColor: Colors.white,
                    backgroundColor: _palette.surface,
                      foregroundColor: _palette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _settingsTile(
                  icon: Icons.notifications_outlined,
                  iconBg: _tealLight,
                  iconColor: _teal,
                  title: 'Notifications',
                  subtitle: 'Alert preferences for session events',
                  trailing: Switch(
                    value: true,
                    activeTrackColor: _teal,
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(height: 14),
                _settingsTile(
                  icon: Icons.fullscreen_rounded,
                  iconBg: _greenLight,
                  iconColor: _green,
                  title: 'Kiosk Mode',
                  subtitle: 'Fullscreen kiosk hardening is active',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _greenLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _green.withValues(alpha: 0.25)),
                    ),
                    child: Text('ACTIVE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _green)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(Icons.info_outline_rounded, 'About', 'App information'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _tealLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _tealAlpha),
                            ),
                            child: Icon(Icons.school_rounded, color: _teal, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('IntelliAttend SmartBoard',
                                  style: TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w800, color: _palette.textPrimary)),
                              const SizedBox(height: 3),
                              Text('Version 5.5.0',
                                  style: TextStyle(
                                      fontSize: 12, color: _palette.textMuted)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(height: 1, color: _palette.border),
                      const SizedBox(height: 16),
                      _infoRow(Icons.construction_rounded, 'Platform', 'Windows'),
                      _infoRow(Icons.tag_rounded, 'Session', widget.sessionId),
                      _infoRow(Icons.meeting_room_outlined, 'Room', widget.roomName),
                      _infoRow(Icons.person_outline_rounded, 'Faculty', widget.facultyName),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _palette.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: _palette.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _teal.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: _palette.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _palette.textPrimary)),
          ),
        ],
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
