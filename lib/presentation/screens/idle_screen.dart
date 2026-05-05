// Pure Firestore snapshots() - exactly like mobile apps
// No server API calls, no polling, no heartbeats

import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../services/device_service.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/secure_storage_service.dart';
import '../../models/isar_schemas.dart';
import '../widgets/glass_container.dart';
import '../widgets/pin_input.dart';
import '../widgets/timeline_slot.dart';
import 'attendance_screen.dart';
import 'settings_screen.dart';
import 'timetable_screen.dart';
import 'analytics_screen.dart';
import 'notifications_screen.dart';

class IdleScreen extends StatefulWidget {
  final DeviceRegistration registration;
  const IdleScreen({super.key, required this.registration});
  
  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen> {
  TimetableEntry? _bedrockEntry;
  List<TimetableEntry> _todayTimeline = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _streamError;
  StreamSubscription<List<TimetableEntry>>? _timetableSubscription;
  StreamSubscription<Map<String, dynamic>?>? _sessionSubscription;
  Timer? _preClassTimer;
  TimetableEntry? _upcomingSlot;
  bool _showStartingSoon = false;
  bool _isKeypadVisible = false;
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startRealTimeListener();
    _startPreClassTimer();
  }

  @override
  void dispose() {
    _timetableSubscription?.cancel();
    _sessionSubscription?.cancel();
    _preClassTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startRealTimeListener() {
    if (Firebase.apps.isEmpty) {
      setState(() => _streamError = 'Firebase not initialized');
      return;
    }
    
    final roomId = widget.registration.roomId;
    
    _timetableSubscription = DeviceService.watchTodaySchedule(roomId).listen(
      (entries) {
        if (mounted) {
          setState(() {
            _todayTimeline = entries;
            _bedrockEntry = _findCurrentSlot(entries);
          });
        }
      },
      onError: (e) => Log.e('❌ [Idle] Timetable stream error: $e'),
    );

    _sessionSubscription = DeviceService.watchActiveSession(roomId).listen(
      (sessionData) {
        if (mounted && sessionData != null) {
          _igniteWithActiveSession(sessionData);
        }
      },
      onError: (e) => Log.e('❌ [Idle] Session stream error: $e'),
    );
  }

  void _igniteWithActiveSession(Map<String, dynamic> data) async {
    final sessionId = data['session_id']?.toString();
    var sessionSecret = data['session_secret']?.toString();
    
    if (sessionId != null && (sessionSecret == null || sessionSecret.isEmpty)) {
      sessionSecret = await SecureStorageService.getSessionSecret(sessionId);
    }

    if (sessionId != null && sessionSecret != null && sessionSecret.isNotEmpty) {
      final course = data['course_name']?.toString() ?? _bedrockEntry?.courseName ?? 'Active Class';
      final faculty = data['faculty_name']?.toString() ?? _bedrockEntry?.facultyName ?? 'Professor';
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(
              sessionId: sessionId,
              sessionSecret: sessionSecret!,
              capacity: widget.registration.capacity,
              courseName: course,
              facultyName: faculty,
            ),
          ),
        );
      }
    }
  }

  TimetableEntry? _findCurrentSlot(List<TimetableEntry> entries) {
    if (entries.isEmpty) return null;
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    for (final entry in entries) {
      if (entry.startTime.compareTo(timeStr) <= 0 && entry.endTime.compareTo(timeStr) > 0) {
        return entry;
      }
    }
    return null;
  }

  void _startPreClassTimer() {
    _preClassTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkUpcomingClass();
    });
    _checkUpcomingClass();
  }

  void _checkUpcomingClass() {
    if (_todayTimeline.isEmpty) return;
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    TimetableEntry? nextSlot;
    for (final entry in _todayTimeline) {
      if (entry.startTime.compareTo(timeStr) > 0) {
        nextSlot = entry;
        break;
      }
    }
    if (nextSlot != null) {
      final parts = nextSlot.startTime.split(':');
      final startTime = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      final diff = startTime.difference(now).inMinutes;
      if (diff >= 0 && diff <= 2) {
        if (mounted && !_showStartingSoon) setState(() { _upcomingSlot = nextSlot; _showStartingSoon = true; });
      } else {
        if (mounted && _showStartingSoon) setState(() => _showStartingSoon = false);
      }
    } else {
      if (mounted && _showStartingSoon) setState(() => _showStartingSoon = false);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit PIN');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await ApiService.initiateSession(otp);
      final data = result['data'] ?? result;
      final sessionId = data['session_id']?.toString();
      final sessionSecret = data['session_secret']?.toString();
      final rosterCount = data['roster_count'] is int ? data['roster_count'] : int.tryParse(data['roster_count']?.toString() ?? '0') ?? 0;
      final facultyName = data['faculty_name']?.toString() ?? 'Professor';
      final courseName = data['course_name']?.toString() ?? 'Active Class';
      final sectionId = data['section_id']?.toString() ?? widget.registration.roomId;

      if (sessionId == null || sessionSecret == null) throw Exception('Invalid server response');

      await SessionManager.saveSession(
        sessionId: sessionId, rosterCount: rosterCount, facultyName: facultyName,
        courseName: courseName, sectionId: sectionId, endTime: DateTime.now().add(const Duration(hours: 1)),
      );
      await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(
              sessionId: sessionId, sessionSecret: sessionSecret,
              capacity: rosterCount > 0 ? rosterCount : widget.registration.capacity,
              courseName: courseName, facultyName: facultyName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background - Base Color
          Container(color: isDark ? AppColors.bgDark : AppColors.bgLight),

          Opacity(
            opacity: isDark ? 0.08 : 0.05,
            child: Image.asset(
              'assets/background.png',
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
            ),
          ),


          // Main Layout
          Column(
            children: [
              _buildTopHeader(isDark),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 80),
                  child: Row(
                    children: [
                      // Left Content: Course Info
                      Expanded(
                        flex: 6,
                        child: _buildCourseInfo(isDark),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        flex: 4,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: _buildAuthCard(isDark, size),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildFooter(isDark, size),
            ],
          ),

          if (_showStartingSoon && _upcomingSlot != null) _buildStartingSoonBanner(),
        ],
      ),
    );
  }

  Widget _buildTopHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.bgDark : Colors.white).withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Text(
            'IntelliAttend SmartBoard',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryTeal,
              letterSpacing: -1,
            ),
          ),
          const Spacer(),
          _buildNavLinks(isDark),
          const SizedBox(width: 40),
          _buildHeaderActions(isDark),
        ],
      ),
    );
  }

  Widget _buildNavLinks(bool isDark) {
    final activeColor = AppColors.primaryTeal;
    final inactiveColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    
    return Row(
      children: [
        _navItem('Welcome', activeColor, true, () {}),
        const SizedBox(width: 30),
        _navItem('Timetable', inactiveColor, false, () {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => TimetableScreen(todayTimeline: _todayTimeline)));
        }),
        const SizedBox(width: 30),
        _navItem('Analytics', inactiveColor, false, () {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AnalyticsScreen()));
        }),
      ],
    );
  }

  Widget _navItem(String label, Color color, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 4),
              height: 2,
              width: 40,
              color: color,
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderActions(bool isDark) {
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    return Row(
      children: [
        IconButton(
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => const NotificationsScreen()));
          }, 
          icon: Icon(Icons.notifications_none, color: iconColor)
        ),
        IconButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IntelliAttend Support: Help is on the way!')));
          }, 
          icon: Icon(Icons.help_outline, color: iconColor)
        ),
        IconButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => SettingsScreen(registration: widget.registration)),
            );
          }, 
          icon: Icon(Icons.settings_outlined, color: iconColor)
        ),
      ],
    );
  }

  Widget _buildCourseInfo(bool isDark) {
    final course = _bedrockEntry?.courseName ?? 'ADVANCED DATA STRUCTURES';
    final faculty = _bedrockEntry?.facultyName ?? 'PROF. DR. SARAH JAY';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Professor Info at Top
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: const Icon(Icons.school_outlined, color: AppColors.primaryTeal),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faculty.toUpperCase(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  'Computer Science Department • Hall 402',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 48),
        // Title Below
        Text(
          course.toUpperCase(),
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppColors.textPrimaryLight,
            height: 1.1,
            letterSpacing: -2,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard(bool isDark, Size size) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.8),
      borderColor: isDark ? Colors.white10 : Colors.black12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'START ATTENDANCE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              Icon(Icons.lock_open_outlined, size: 20, color: isDark ? Colors.white24 : Colors.black26),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the session code displayed on your mobile device to begin Session.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => setState(() => _isKeypadVisible = !_isKeypadVisible),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: PinInput(value: _otpController.text),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _buildNumericKeypad(isDark),
            ),
            crossFadeState: _isKeypadVisible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 400),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleVerifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 10),
                        const Text('SUBMIT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STATUS: READY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryTeal)),
                  const SizedBox(width: 8),
                  Text(
                    'ENCRYPTED SESSION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark, Size size) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.bgDark : Colors.white).withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          // Timeline
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _todayTimeline.isEmpty ? 5 : _todayTimeline.length,
              itemBuilder: (context, index) {
                if (_todayTimeline.isEmpty) {
                  return TimelineSlot(
                    entry: TimetableEntry()
                      ..courseName = 'CS302 - Data Structures'
                      ..facultyName = 'Dr. Sarah'
                      ..startTime = '09:30 AM'
                      ..endTime = '10:30 AM',
                    isLive: index == 2,
                  );
                }
                final entry = _todayTimeline[index];
                return TimelineSlot(
                  entry: entry,
                  isLive: entry.id == _bedrockEntry?.id,
                );
              },
            ),
          ),
          const SizedBox(width: 40),
          // Clock & Students
          _buildClockAndInfo(isDark),
        ],
      ),
    );
  }

  Widget _buildClockAndInfo(bool isDark) {
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final timeStr = "${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')}";
        final period = now.hour >= 12 ? 'PM' : 'AM';
        
        return Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.group_outlined, size: 16, color: AppColors.primaryTeal),
                    const SizedBox(width: 8),
                    Text(
                      '142 Students Present',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 120,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.85,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(margin: const EdgeInsets.symmetric(horizontal: 24), height: 40, width: 1, color: isDark ? Colors.white10 : Colors.black12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$timeStr $period",
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  _getFormattedDate(now).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _getFormattedDate(DateTime now) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}";
  }

  Widget _buildStartingSoonBanner() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        height: 60,
        color: AppColors.primaryTeal,
        child: Center(
          child: Text(
            'CLASS STARTING SOON: ${_upcomingSlot!.courseName.toUpperCase()}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ),
      ),
    );
  }


  Widget _buildNumericKeypad(bool isDark) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++) _keypadButton(i.toString(), isDark),
        const SizedBox(),
        _keypadButton('0', isDark),
        _keypadButton('backspace', isDark, isAction: true),
      ],
    );
  }

  Widget _keypadButton(String label, bool isDark, {bool isAction = false}) {
    return InkWell(
      onTap: () {
        if (label == 'backspace') {
          if (_otpController.text.isNotEmpty) {
            setState(() => _otpController.text = _otpController.text.substring(0, _otpController.text.length - 1));
          }
        } else {
          if (_otpController.text.length < 6) {
            setState(() => _otpController.text += label);
          }
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Center(
          child: label == 'backspace'
              ? Icon(Icons.backspace_outlined, size: 16, color: isDark ? Colors.white38 : Colors.black38)
              : Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
        ),
      ),
    );
  }
}

