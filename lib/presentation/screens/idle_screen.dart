// Isar-local schedule data, REST-only sync on boot/day-change.
// No Firestore snapshot listeners — zero continuous read cost.

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/config/app_config.dart';
import '../../core/telemetry/metrics_collector.dart';
import '../../core/utils/logger.dart';
import '../../data/repositories/device_repository.dart';
import 'package:provider/provider.dart';
import '../../services/session_manager.dart';
import '../../main.dart';
import '../../services/api_service.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/session_secret_vault.dart';
import '../../core/rate_limiter.dart';
import '../../models/isar_schemas.dart';
import '../widgets/glass_container.dart';
import '../widgets/pin_input.dart';
import '../widgets/timeline_slot.dart';
import 'registration_screen.dart';
import 'attendance_screen.dart';
import 'settings_screen.dart';
import 'timetable_screen.dart';
import 'analytics_screen.dart';
import 'notifications_screen.dart';
import '../../services/time_sync_service.dart';
import '../../services/timetable_cache.dart';
import 'package:video_player/video_player.dart';
import '../../services/pre_flight_service.dart';
import '../../services/totp_engine.dart';
import '../../core/platform/kiosk_service.dart';

enum PreFlightStatus { none, connecting, ready }

class IdleScreen extends StatefulWidget {
  final DeviceRegistration registration;
  const IdleScreen({super.key, required this.registration});
  
  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen> with SingleTickerProviderStateMixin {
  TimetableEntry? _bedrockEntry;
  List<TimetableEntry> _todayTimeline = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _preClassTimer;
  TimetableEntry? _upcomingSlot;
  bool _showStartingSoon = false;
  bool _isKeypadVisible = false;
  Timer? _inactivityTimer;
  final TextEditingController _otpController = TextEditingController();
  final int _presentCount = 0;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  String _idleTheme = 'auto'; // 'auto', 'white', or 'dark'
  bool _forceShowCard = false; // For starting session in advance via lock icon tap

  // Session ID received from the preflight API response (_triggerWarmUp).
  // Stored here in RAM so OTP submission (_handleVerifyOtp) can use it
  // directly. Falls back to initiateSession() API response if this is null.
  String? _preAllocatedSessionId;
  PreFlightStatus _preFlightStatus = PreFlightStatus.none;
  bool _isReadyCheckDone = false;
  bool _preFlightForceAttempted = false;
  String? _currentSlotWarmUpSlotId;
  /// Tracks which upcoming slot's warm-up has been initiated so the 10-second
  /// [_preClassTimer] in [_checkUpcomingClass] does NOT re-trigger a warm-up
  /// that already failed. Without this guard, the UI cycles through
  /// PENDING → WARMING UP... → PENDING → WARMING UP... every 10 seconds.
  String? _warmUpTriggeredSlotId;
  StreamSubscription<dynamic>? _preFlightSessionSubscription; // cleanup handle for warm-up

  // Listens to the global TimetableCache — every Firestore snapshot update
  // triggers _onTimetableCacheChanged which re-reads today's entries from RAM
  // and calls setState, keeping the entire idle UI in sync without polling.
  void _onTimetableCacheChanged() {
    if (mounted) {
      setState(() {
        _todayTimeline = TimetableCache().todayTimeline;
        _bedrockEntry = TimetableCache().currentSlot;
      });
    }
  }

  // Cinematic Transition
  late AnimationController _cinematicController;
  DateTime? _breakStartedAt;
  Timer? _cinematicTimer;
  bool _isCinematicTransitionTriggered = false;

  @override
  void initState() {
    super.initState();

    // Only build the animation controller and read local caches synchronously.
    // Anything that touches window_manager, Firestore, or video network I/O is
    // deferred to a post-frame callback so it cannot race against Flutter's
    // first-frame commit on Windows (the cause of the silent engine crash).
    _cinematicController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() => setState(() {}));

    // Load timetable from Isar + subscribe to in-memory cache for live updates.
    // The cache is the single source of truth for the current slot — the local
    // _findCurrentSlot is removed in favour of TimetableCache().currentSlot.
    _loadInitialData();   // Isar read — local only, safe.
    _loadPreferences();   // SecureStorage read — local only, safe.

    // Subscribe to the global timetable cache. Every update from the
    // Firestore listener flows through TimetableCache → this callback,
    // keeping the idle UI in sync with zero polling overhead.
    TimetableCache().addListener(_onTimetableCacheChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 1. Set kiosk mode FIRST so window state is settled before any
      //    Firebase auth callbacks arrive on background threads.
      await KioskService.setMode(KioskMode.fullscreen);

      if (!mounted) return;

      // 2. Start global background protocols (SyncManager, WindowOrchestrator,
      //    PreFlightService). These open Firestore listeners + a Timer that
      //    can call window_manager. Now safe because setMode has completed.
      await startBackgroundProtocols();

      if (!mounted) return;

      // 3. One-shot REST sync to guarantee fresh data on boot.
      //    The Firestore snapshot listener keeps the cache + Isar updated
      //    going forward, so subsequent sync calls are no longer needed.
      await context.read<IDeviceRepository>().syncTimetable(fullSync: true);
      _refreshTimetable();
      _checkCrashRecovery();
      _startPreClassTimer();
      _startCinematicMonitor();
      if (AppConfig.enableVideoBreaks) {
        _initVideoBackground();
      }
    });
  }


  void _startCinematicMonitor() {
    _cinematicTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final isBreak = _isAnyBreak();
      final hasVideo = isBreak && _isVideoInitialized && _videoController != null;

      // Reset to White (0.0) if no video is playing OR if we are forcing the card (Session Active)
      if (!hasVideo || _forceShowCard) {
        if (_cinematicController.value > 0) _cinematicController.reverse();
        _breakStartedAt = null;
        _isCinematicTransitionTriggered = false;
        return;
      }

      // Respect user preference if not set to 'auto'
      if (_idleTheme == 'white') {
        if (_cinematicController.value > 0) _cinematicController.reverse();
        return;
      }
      if (_idleTheme == 'dark') {
        if (_cinematicController.value < 1) _cinematicController.forward();
        return;
      }

      // Automatic logic
      if (_breakStartedAt == null) {
        _breakStartedAt = DateTime.now();
        _cinematicController.reverse(); // Start at White (0.0)
      }

      // After 3 minutes (Production Logic), transition to Dark (1.0)
      final elapsedMinutes = TimeSyncService.timeNow.difference(_breakStartedAt!).inMinutes;
      if (elapsedMinutes >= 3 && !_isCinematicTransitionTriggered && !_showStartingSoon) {
        _isCinematicTransitionTriggered = true;
        _cinematicController.forward();
      }

      // 3 minutes before next class, transition back to White (0.0)
      if (_showStartingSoon && _cinematicController.value > 0 && _cinematicController.status != AnimationStatus.reverse) {
        _cinematicController.reverse();
        _isCinematicTransitionTriggered = false;
      }
    });
  }

  Future<void> _loadPreferences() async {
    final theme = await SecureStorageService.getIdleTheme();
    if (mounted) {
      setState(() {
        _idleTheme = theme ?? 'auto';
      });
    }
  }

  void _initVideoBackground() {
    // Verified macOS compatible testing URL for verification
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse('https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4'),
    )..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
            _videoController?.setLooping(true);
            _videoController?.setVolume(0);
            _videoController?.play();
          });
        }
      }).catchError((e) {
        Log.e('❌ [Video] Failed to initialize: $e');
        if (mounted) {
          setState(() {
            _isVideoInitialized = false;
          });
        }
      });
  }

  bool _isAnyBreak() {
    if (!AppConfig.enableVideoBreaks) return false;
    return _isBioBreak() || _isLunchBreak();
  }

  int _toMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int _currentGapMinutes() {
    if (_todayTimeline.isEmpty) return 0;
    final now = TimeSyncService.timeNow;
    final nowMinutes = now.hour * 60 + now.minute;
    final sorted = List<TimetableEntry>.from(_todayTimeline)
      ..sort((a, b) => _toMinutes(a.startTime).compareTo(_toMinutes(b.startTime)));
    for (int i = 0; i < sorted.length - 1; i++) {
      final prevEnd = _toMinutes(sorted[i].endTime);
      final nextStart = _toMinutes(sorted[i + 1].startTime);
      int gap = nextStart - prevEnd;
      if (gap < -1200) gap += 1440;
      if (gap >= 5 && nowMinutes >= prevEnd && nowMinutes < nextStart) return gap;
    }
    return 0;
  }

  bool _isBioBreak() {
    final gap = _currentGapMinutes();
    return gap > 0 && gap <= 15;
  }

  bool _isLunchBreak() {
    final gap = _currentGapMinutes();
    return gap > 15;
  }

  bool _isPreBootPhase() {
    if (_bedrockEntry != null || _todayTimeline.isEmpty) return false;
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;
    final firstEntry = _todayTimeline.first;
    final parts = firstEntry.startTime.split(':');
    if (parts.length != 2) return false;
    int firstStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    int diff = firstStart - currentMinutes;
    if (diff < -1200) diff += 1440;
    return diff > 0 && diff <= 10;
  }

  bool _isEveningPhase() {
    if (_todayTimeline.isEmpty || _bedrockEntry != null) return false;
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;
    for (final entry in _todayTimeline) {
      final parts = entry.startTime.split(':');
      if (parts.length != 2) continue;
      int startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (startMinutes > currentMinutes) return false;
    }
    final lastEntry = _todayTimeline.last;
    final endParts = lastEntry.endTime.split(':');
    if (endParts.length != 2) return false;
    int lastEndMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    return currentMinutes > lastEndMinutes;
  }

  String _getBreakTip() {
    final tips = [
      "Stay hydrated! Grab a glass of water.",
      "Stretch your legs and take a deep breath.",
      "Rest your eyes - look at something 20 feet away.",
      "A quick walk can boost your focus for the next session.",
    ];
    return tips[TimeSyncService.timeNow.minute % tips.length];
  }

  Future<void> _loadInitialData() async {
    final deviceRepository = context.read<IDeviceRepository>();
    final initialTimeline = await deviceRepository.getTodayTimeline();
    if (mounted) {
      setState(() {
        _todayTimeline = initialTimeline;
        _bedrockEntry = TimetableCache().currentSlot;
      });
    }
  }

  @override
  void dispose() {
    TimetableCache().removeListener(_onTimetableCacheChanged);
    _cinematicTimer?.cancel();
    _videoController?.dispose();
    _otpController.dispose();
    _inactivityTimer?.cancel();
    _preClassTimer?.cancel();
    _preFlightSessionSubscription?.cancel();
    _cinematicController.dispose();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _forceShowCard) {
        setState(() {
          _forceShowCard = false;
          _otpController.clear();
        });
      }
    });
  }

  /// Refreshes timetable from local Isar storage.
  /// Called after the one-shot REST sync on boot. Once the Firestore
  /// snapshot listener fires, the [TimetableCache] listener handles
  /// subsequent reactive updates.
  Future<void> _refreshTimetable() async {
    final deviceRepository = context.read<IDeviceRepository>();
    final entries = await deviceRepository.getTodayTimeline();
    if (mounted) {
      setState(() {
        _todayTimeline = entries;
        _bedrockEntry = TimetableCache().currentSlot;
      });
    }
  }

  /// Checks the local Isar vault + SecureStorage for a resumable session.
  /// If one exists (e.g. the board crashed mid-session), navigates straight
  /// to AttendanceScreen — no OTP re-entry needed.
  /// This is the sole crash-recovery path — no Firestore listeners needed.
  Future<void> _checkCrashRecovery() async {
    try {
      final session = await SessionManager.getResumeableSession();
      if (session == null) return;

      final secret =
          await SecureStorageService.getSessionSecret(session.sessionId);
      if (secret == null || secret.isEmpty) return;

      Log.i(
          '[Idle] Crash recovery: resuming session ${session.sessionId}');
      if (mounted) {
        final engine = TotpEngine(
          sessionId: session.sessionId,
          sessionSecret: secret,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(
              sessionId: session.sessionId,
              totpEngine: engine,
              capacity: widget.registration.capacity,
              courseName: session.courseName,
              facultyName: session.facultyName,
              sectionId: session.sectionId,
              roomName: widget.registration.roomName,
            ),
          ),
        );
      }
    } catch (e) {
      Log.w('⚠️ [Idle] Crash recovery check failed: $e');
    }
  }
  /// Helper to derive the final secret using the hardware fingerprint (Atomic Logic)
  Future<String?> _deriveSecret(Map<String, dynamic> data) async {
    final half1 = data['session_secret_half1']?.toString();
    if (half1 == null) return null;

    final deviceId = await HardwareFingerprintService.getDeviceId();
    final half2 = Hmac(sha256, utf8.encode(deviceId))
        .convert(utf8.encode(half1))
        .toString()
        .substring(0, 16);
    return '$half1$half2';
  }

  void _startPreClassTimer() {
    _preClassTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {
          _bedrockEntry = TimetableCache().currentSlot;
        });
      }
      Log.i('[IdleTimer] tick: bedrockEntry.slotId=${_bedrockEntry?.slotId}  timelineCount=${TimetableCache().todayTimeline.length}  now=${TimeSyncService.timeNow.hour}:${TimeSyncService.timeNow.minute}');
      _checkUpcomingClass();
      _checkDayChange();
    });
    _checkUpcomingClass();
  }

  int? _lastQueryDay;
  void _checkDayChange() {
    final today = TimeSyncService.timeNow.weekday;
    if (_lastQueryDay != null && _lastQueryDay != today) {
      Log.i('📅 [Idle] Day changed from $_lastQueryDay to $today. Refreshing from cache...');
      _lastQueryDay = today;
      _refreshTimetable();
    }
    _lastQueryDay ??= today;
  }

  void _checkUpcomingClass() {
    if (_todayTimeline.isEmpty) return;
    
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;
    
    TimetableEntry? nextEntry;
    int minDiff = 9999;

    for (final entry in _todayTimeline) {
      final parts = entry.startTime.split(':');
      if (parts.length != 2) continue;
      
      int entryMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      int diff = entryMinutes - currentMinutes;
      
      // Handle wraparound (e.g. current 23:50, next 00:50)
      if (diff < -1200) { // If entry is more than 20 hours in the "past", it's likely tomorrow early morning
        diff += 1440; // 24 hours
      }
      
      if (diff > 0 && diff < minDiff) {
        minDiff = diff;
        nextEntry = entry;
      }
    }

    if (nextEntry != null && minDiff <= 3) {
      if (mounted) {
        setState(() {
          _upcomingSlot = nextEntry;
          _showStartingSoon = true;
        });
        
        // Trigger Per-Session Warm-Up — only ONCE per slot so the timer does
        // NOT re-trigger after a failed API call every 10 seconds (which would
        // cause the UI to cycle through PENDING → WARMING UP... → PENDING).
        if (_preFlightStatus == PreFlightStatus.none &&
            _warmUpTriggeredSlotId != nextEntry.slotId) {
          _warmUpTriggeredSlotId = nextEntry.slotId;
          _triggerWarmUp(nextEntry.slotId);
        }

        // v6.1 Phase 3: Silent Health Check at T-1m
        if (minDiff == 1 && !_isReadyCheckDone) {
          _isReadyCheckDone = true;
          ApiService.syncReadyCheck().catchError((e) => Log.w('⚠️ Ready check failed: $e'));
        }

        // v6.1 Fallback: Force a fresh preflight attempt at T-0
        if (minDiff == 0 && _preFlightStatus != PreFlightStatus.ready) {
          if (_upcomingSlot != null && !_preFlightForceAttempted) {
            _preFlightForceAttempted = true;
            _triggerWarmUp(_upcomingSlot!.slotId, force: true);
          }
          setState(() {
            _errorMessage = 'System sync delayed. Enter PIN to proceed.';
          });
        }
      }
    } else {
      _isReadyCheckDone = false;
      // Check for Daily Boot (10 min before first class)
      // Since _todayTimeline is already sorted by academic day in DeviceService, we just check the first item
      if (nextEntry != null && minDiff <= 10) {
        final bool isFirstClass = _todayTimeline.isNotEmpty && _todayTimeline.first.slotId == nextEntry.slotId;
        if (isFirstClass) {
          PreFlightService().runDailyBoot();
        }
      }

      if (mounted && _showStartingSoon && minDiff > 5) {
        setState(() {
          _showStartingSoon = false;
          _upcomingSlot = null;
          _forceShowCard = false;
          _preFlightStatus = PreFlightStatus.none;
          _preFlightForceAttempted = false;
          _warmUpTriggeredSlotId = null;
          _preFlightSessionSubscription?.cancel();
          // Clear stale pre-allocated ID — a new one will arrive from the
          // next preflight API call when the following slot's T-3 window opens.
          _preAllocatedSessionId = null;
        });
      }

      // Fallback: current class in progress with no session yet.
      // Does NOT require nextEntry == null — the current slot might be LIVE
      // even when there are later classes today. The _preAllocatedSessionId
      // guard prevents redundant triggers.
      if (_bedrockEntry != null && _preAllocatedSessionId == null) {
        final currentSlotId = _bedrockEntry!.slotId;
        if (_currentSlotWarmUpSlotId != currentSlotId) {
          _currentSlotWarmUpSlotId = currentSlotId;
          Log.i('[Idle] Current class $currentSlotId in progress — triggering warm-up.');
          _triggerWarmUp(currentSlotId);
        }
      } else if (_bedrockEntry == null) {
        _currentSlotWarmUpSlotId = null;
      }
    }
  }


  void _triggerWarmUp(String slotId, {bool force = false}) async {
    try {
      setState(() {
        _preFlightStatus = PreFlightStatus.connecting;
        _errorMessage = null;
      });

      // Callback that fires both on the initial call AND on every retry
      // success inside PreFlightService. This ensures the UI updates to
      // "ready" when a delayed retry finally succeeds.
      void onWarmUpSuccess(Map<String, dynamic> result) {
        if (!mounted) return;
        if (result['pre_allocated_session_id'] != null) {
          final pid = result['pre_allocated_session_id']?.toString();
          setState(() {
            _preFlightStatus = PreFlightStatus.ready;
            _preAllocatedSessionId = pid;
            _errorMessage = null;
          });
          Log.i('✅ [Idle] Board ARMED. SessionID in RAM: $pid.');
        }
      }

      final result = force
          ? await PreFlightService().forceWarmUp(slotId,
              onSuccess: onWarmUpSuccess)
          : await PreFlightService().runPerSessionWarmUp(slotId,
              onSuccess: onWarmUpSuccess);

      if (result == null && mounted) {
        // Initial attempt failed — the onSuccess callback will still fire
        // later if a PreFlightService retry eventually succeeds.
        setState(() => _preFlightStatus = PreFlightStatus.none);
      }
    } catch (e) {
      if (mounted) {
        if (e is UnregisteredException) {
          Log.w('🚨 [IdleScreen] Pre-flight failed: Device unregistered. Redirecting...');
          await context.read<IDeviceRepository>().clearRegistration();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const RegistrationScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() => _preFlightStatus = PreFlightStatus.none);
          Log.w('⚠️ [Idle] Pre-flight failed. Faculty may still proceed manually: $e');
        }
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit PIN');
      return;
    }

    // Try pre-flight warm-up once if session ID is missing. If retries
    // exhausted, fall back to the session ID from the initiateSession API.
    if (_preAllocatedSessionId == null) {
      if (_upcomingSlot != null) {
        _triggerWarmUp(_upcomingSlot!.slotId, force: true);
      }
      if (_preAllocatedSessionId == null) {
        Log.w('[Idle] Pre-flight unavailable. Faculty may proceed with API-provided session ID.');
      }
    }

    final rateKey = 'session_pin_${widget.registration.smartBoardId}';
    if (!RateLimiter.isAllowed(rateKey)) {
      setState(() => _errorMessage = 'Too many attempts. Please wait before trying again.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      // Strict OTP Protocol: OTP must never be stored. The text controller is
      // cleared the instant the API call fires — before waiting for a response.
      _otpController.clear();

      final result = await ApiService.initiateSession(otp);
      RateLimiter.reset(rateKey);
      final data = result['data'] ?? result;

      // Pre-allocated session ID from warm-up is authoritative if available.
      // Fall back to the API response when retries were exhausted.
      final sessionId =
          _preAllocatedSessionId ?? data['session_id']?.toString();

      final sessionSecret = await _deriveSecret(data);

      final rosterCount = data['roster_count'] is int ? data['roster_count'] : int.tryParse(data['roster_count']?.toString() ?? '0') ?? 0;
      final facultyName = data['faculty_name']?.toString() ?? 'Professor';
      final courseName = data['course_name']?.toString() ?? 'Active Class';
      final sectionId = data['section_id']?.toString() ?? widget.registration.smartBoardId;

      if (sessionId == null || sessionSecret == null) {
        setState(() => _errorMessage = 'Invalid server response: missing session data. Please try again with a new PIN.');
        return;
      }

      await SessionManager.saveSession(
        sessionId: sessionId, rosterCount: rosterCount, facultyName: facultyName,
        courseName: courseName, sectionId: sectionId, endTime: TimeSyncService.timeNow.add(const Duration(hours: 1)),
      );
      MetricsCollector().recordSessionStart();
      await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);

      // Session is now live — clear the in-memory pre-allocated ID so it
      // cannot be accidentally reused if the board returns to IdleScreen.
      if (mounted) setState(() => _preAllocatedSessionId = null);

      if (mounted) {
        final engine = TotpEngine(
          sessionId: sessionId,
          sessionSecret: sessionSecret,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(
              sessionId: sessionId,
              totpEngine: engine,
              capacity: widget.registration.capacity,
              courseName: courseName,
              facultyName: facultyName,
              sectionId: sectionId,
              roomName: widget.registration.roomName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is UnregisteredException) {
          Log.w('🚨 [IdleScreen] Device unregistered on server. Redirecting to Registration...');
          await context.read<IDeviceRepository>().clearRegistration();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const RegistrationScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isBreak = _isAnyBreak();
    final showVideo = isBreak && _isVideoInitialized && _videoController != null;
    
    // Theme Calculation Logic:
    // If showVideo is false OR session is being initiated (forceShowCard), we are "Blindly White"
    final bool isBlindlyWhite = !showVideo || _forceShowCard;
    final morph = isBlindlyWhite ? 0.0 : _cinematicController.value;
    
    final overlayColor = Color.lerp(
      Colors.white.withValues(alpha: 0.1),
      Colors.black.withValues(alpha: 0.4),
      morph
    )!;
    
    final headerFooterColor = Color.lerp(
      Colors.white,
      AppColors.bgDark,
      morph
    )!;

    final primaryTextColor = Color.lerp(
      AppColors.textPrimaryLight,
      Colors.white,
      morph
    )!;

    final secondaryTextColor = Color.lerp(
      AppColors.textSecondaryLight,
      AppColors.textSecondaryDark,
      morph
    )!;

    // Context-Aware Visibility:
    // 1. OTP card only appears when user taps the unlocked lock icon (at T-3).
    // 2. Otherwise, show the lock symbol (unlocked at T-3, locked otherwise).
    final bool showCardContextually = _forceShowCard;
    
    final cardOpacity = showCardContextually ? 1.0 : 0.0;
        
    final lockOpacity = showCardContextually ? 0.0 : 1.0;

    List<Widget> stackChildren = [];
    
    // 1. Background
    if (showVideo) {
      stackChildren.add(
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        )
      );
    } else {
      stackChildren.add(Container(color: isDark ? AppColors.bgDark : AppColors.bgLight));
    }

    // 2. Overlay
    if (showVideo) {
      stackChildren.add(Container(decoration: BoxDecoration(color: overlayColor)));
    }

    // 3. Logo
    if (!showVideo) {
      stackChildren.add(
        Opacity(
          opacity: isDark ? 0.05 : 0.03,
          child: Center(
            child: Image.asset(
              'assets/background.png',
              width: size.width * 0.6,
              fit: BoxFit.contain,
            ),
          ),
        )
      );
    }

    // 4. Main UI
    stackChildren.add(
      Column(
        children: [
          _buildTopHeader(primaryTextColor, headerFooterColor, showVideo),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: _buildCourseInfo(primaryTextColor, secondaryTextColor, showVideo),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    flex: 4,
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Opacity(
                          opacity: cardOpacity,
                          child: IgnorePointer(
                            ignoring: cardOpacity < 0.1,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: _buildAuthCard(
                                isBlindlyWhite ? Colors.white : headerFooterColor,
                                isBlindlyWhite ? AppColors.textPrimaryLight : primaryTextColor,
                                isBlindlyWhite ? AppColors.textSecondaryLight : secondaryTextColor,
                                showVideo && !isBlindlyWhite
                              ),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: lockOpacity,
                          child: IgnorePointer(
                            ignoring: lockOpacity < 0.1,
                            child: _buildHangingLock(primaryTextColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildFooter(headerFooterColor, primaryTextColor, secondaryTextColor, showVideo),
        ],
      )
    );

    // 5. Banner
    if (_showStartingSoon && _upcomingSlot != null) {
      stackChildren.add(_buildStartingSoonBanner());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: stackChildren),
    );
  }

  Widget _buildTopHeader(Color textColor, Color bgColor, bool isVideoActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.8),
        border: Border(bottom: BorderSide(color: textColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Text(
            'IntelliAttend SmartBoard',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textColor == Colors.white ? Colors.white : AppColors.primaryTeal,
              letterSpacing: -1,
            ),
          ),
          const Spacer(),
          _buildNavLinks(textColor),
          const SizedBox(width: 40),
          _buildHeaderActions(textColor),
        ],
      ),
    );
  }

  String _getPreFlightStatusText() {
    switch (_preFlightStatus) {
      case PreFlightStatus.none: return 'PENDING';
      case PreFlightStatus.connecting: return 'WARMING UP...';
      case PreFlightStatus.ready: return 'READY';
    }
  }

  Color _getIndicatorColor() {
    return _preFlightStatus == PreFlightStatus.ready ? AppColors.successLime : AppColors.primaryTeal;
  }

  Widget _buildNavLinks(Color color) {
    final activeColor = color == Colors.white ? Colors.white : AppColors.primaryTeal;
    final inactiveColor = color == Colors.white ? Colors.white70 : AppColors.textSecondaryLight;
    
    return Row(
      children: [
        _navItem('Welcome', activeColor, true, () {}),
        const SizedBox(width: 30),
        _navItem('Timetable', inactiveColor, false, () {
          final weekly = TimetableCache().weeklyTimeline;
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => TimetableScreen(weeklyTimeline: weekly)));
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

  Widget _buildHeaderActions(Color color) {
    final iconColor = color == Colors.white ? Colors.white70 : Colors.black54;
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
          onPressed: () => KioskService.setMode(KioskMode.suspended),
          icon: Icon(Icons.minimize_rounded, color: iconColor),
          tooltip: 'Minimize to Desktop',
        ),
        IconButton(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsScreen(registration: widget.registration)));
            _loadPreferences();
          }, 
          icon: Icon(Icons.settings_outlined, color: iconColor)
        ),
      ],
    );
  }

  Widget _buildCourseInfo(Color primaryColor, Color secondaryColor, bool isVideoActive) {
    final isSunday = TimeSyncService.timeNow.weekday == DateTime.sunday;
    final isBio = _isBioBreak();
    final isLunch = _isLunchBreak();
    final hasBreak = isBio || isLunch;
    
    var course = _bedrockEntry?.courseName ?? 'NO ACTIVE SESSION';
    var faculty = _bedrockEntry?.facultyName ?? 'SYSTEM READY';
    
    if (isSunday && _bedrockEntry == null) {
      course = 'SUNDAY FUNDAY';
      faculty = 'SYSTEM IDLE';
    } else if (isBio) {
      course = 'BIO BREAK TIME';
      faculty = 'REFRESH';
    } else if (isLunch) {
      course = 'LUNCH BREAK';
      faculty = 'RECHARGE';
    } else if (_bedrockEntry == null && _isEveningPhase()) {
      course = 'HAPPY EVENING';
      faculty = 'HAVE A GREAT DAY';
    } else if (_bedrockEntry == null && _isPreBootPhase()) {
      course = 'GOOD MORNING';
      faculty = 'SYSTEM READY';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Professor Info at Top
        if (!hasBreak && !(isSunday && _bedrockEntry == null))
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor == Colors.white ? AppColors.surfaceDark : Colors.white,
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
                  (faculty.contains('@') ? faculty.split('@')[0].replaceAll('_', ' ').toUpperCase() : faculty.toUpperCase()),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Text(
                  '${widget.registration.roomName} • ${widget.registration.department}',
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
          ],
        )
        else if (hasBreak)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(isBio ? Icons.coffee_outlined : Icons.restaurant_outlined, color: AppColors.primaryTeal),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBio ? 'QUICK REFRESHMENT' : 'MID-DAY MEAL',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryTeal,
                  ),
                ),
                Text(
                  _getBreakTip(),
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryColor,
                    fontStyle: FontStyle.italic,
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
            color: primaryColor,
            height: 1.1,
            letterSpacing: -2,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard(Color bgColor, Color primaryColor, Color secondaryColor, bool isVideoActive) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      color: bgColor.withValues(alpha: 0.8),
      borderColor: primaryColor.withValues(alpha: 0.1),
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
                  color: primaryColor,
                ),
              ),
              Icon(Icons.lock_open_outlined, size: 20, color: secondaryColor.withValues(alpha: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the session code displayed on your mobile device to begin Session.',
            style: TextStyle(
              fontSize: 12,
              color: secondaryColor,
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
              child: _buildNumericKeypad(primaryColor == Colors.white, isVideoActive),
            ),
            crossFadeState: _isKeypadVisible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 400),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                      mainAxisSize: MainAxisSize.min,
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'STATUS: ${_getPreFlightStatusText()}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _getIndicatorColor())),
                  const SizedBox(width: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: const Text(
                      'ENCRYPTED SESSION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
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

  Widget _buildFooter(Color bgColor, Color primaryColor, Color secondaryColor, bool isVideoActive) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.9),
        border: Border(top: BorderSide(color: primaryColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          // Timeline
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _todayTimeline.isEmpty ? 1 : _todayTimeline.length,
              itemBuilder: (context, index) {
                if (_todayTimeline.isEmpty) {
                  if (index > 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Center(
                      child: Text(
                        TimeSyncService.timeNow.weekday == DateTime.sunday ? 'SUNDAY FUNDAY' : 'NO CLASSES SCHEDULED TODAY',
                        style: const TextStyle(color: AppColors.textSecondaryDark, fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ),
                  );
                }
                final entry = _todayTimeline[index];
                final live = entry.slotId == _bedrockEntry?.slotId;
                Log.i('[TimelineStrip] idx=$index slot=${entry.slotId} bedrock.slot=${_bedrockEntry?.slotId} isLive=$live');
                return TimelineSlot(
                  entry: entry,
                  isLive: live,
                );
              },
            ),
          ),
          const SizedBox(width: 40),
          // Clock & Students
          _buildClockAndInfo(primaryColor, secondaryColor),
        ],
      ),
    );
  }

  Widget _buildClockAndInfo(Color primaryColor, Color secondaryColor) {
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(const Duration(seconds: 1), (_) => TimeSyncService.timeNow),
      builder: (context, snapshot) {
        final now = snapshot.data ?? TimeSyncService.timeNow;
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
                      '$_presentCount Students Present',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 120,
                  height: 4,
                  decoration: BoxDecoration(
                    color: secondaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.registration.capacity > 0 
                        ? (_presentCount / widget.registration.capacity).clamp(0.0, 1.0)
                        : 0.0,
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
            Container(margin: const EdgeInsets.symmetric(horizontal: 24), height: 40, width: 1, color: secondaryColor.withValues(alpha: 0.1)),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$timeStr $period",
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Text(
                  _getFormattedDate(now).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: secondaryColor.withValues(alpha: 0.5),
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${dayNames[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}";
  }

  Widget _buildStartingSoonBanner() {
    return Positioned(
      top: 20, left: 0, right: 0,
      child: Center(
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          borderRadius: 30,
          color: AppColors.primaryTeal.withValues(alpha: 0.9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  'CLASS STARTING SOON: ${_upcomingSlot!.courseName.toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHangingLock(Color color) {
    final isUnlocked = _showStartingSoon || _bedrockEntry != null;
    return InkWell(
      onTap: isUnlocked
          ? () {
              setState(() {
                _forceShowCard = true;
              });
              _resetInactivityTimer();
            }
          : null,
      borderRadius: BorderRadius.circular(50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 2,
            height: 40,
            color: color.withValues(alpha: 0.2),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUnlocked
                  ? AppColors.successLime.withValues(alpha: 0.15)
                  : color.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: isUnlocked
                    ? AppColors.successLime.withValues(alpha: 0.3)
                    : color.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              isUnlocked ? Icons.lock_open_outlined : Icons.lock_outline,
              color: isUnlocked ? AppColors.successLime : color.withValues(alpha: 0.5),
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isUnlocked ? 'TAP TO START' : 'SESSION LOCKED',
            style: TextStyle(
              color: isUnlocked ? AppColors.successLime : color.withValues(alpha: 0.3),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildNumericKeypad(bool isDark, bool isVideoActive) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++) _keypadButton(i.toString(), isDark, isVideoActive),
        const SizedBox(),
        _keypadButton('0', isDark, isVideoActive),
        _keypadButton('backspace', isDark, isVideoActive, isAction: true),
      ],
    );
  }

  Widget _keypadButton(String label, bool isDark, bool isVideoActive, {bool isAction = false}) {
    return InkWell(
      onTap: () {
        if (label == 'backspace') {
          if (_otpController.text.isNotEmpty) {
            setState(() {
              _otpController.text = _otpController.text.substring(0, _otpController.text.length - 1);
              _resetInactivityTimer();
            });
          }
        } else {
          if (_otpController.text.length < 6) {
            setState(() {
              _otpController.text += label;
              _resetInactivityTimer();
            });
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

