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
import '../../services/websocket_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/platform/window_orchestrator_service.dart';

enum PreFlightStatus { none, connecting, ready, pending }
enum CooldownState { none, locked }

class IdleScreen extends StatefulWidget {
  final DeviceRegistration registration;

  /// When true, the idle screen waits 3 seconds then minimizes automatically.
  /// Used after attendance completion to return to the OS desktop gracefully.
  final bool completedSession;
  const IdleScreen(
      {super.key, required this.registration, this.completedSession = false});

  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen>
    with SingleTickerProviderStateMixin {
  /// Threshold (in minutes) for detecting midnight wraparound in time-diff
  /// calculations. If a gap between two slots is less than -1200 (i.e. more
  /// than 20 hours negative), it means `nextStart` belongs to the next
  /// calendar day and we add 1440 to get the real positive gap.
  static const int _midnightWrapThreshold = -1200;
  static const int _minutesPerDay = 1440;

  TimetableEntry? _bedrockEntry;
  List<TimetableEntry> _todayTimeline = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _preClassTimer;
  TimetableEntry? _upcomingSlot;
  bool _showStartingSoon = false;
  Timer? _inactivityTimer;
  final TextEditingController _otpController = TextEditingController();

  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  String _idleTheme = 'auto'; // 'auto', 'white', or 'dark'
  bool _forceShowCard =
      false; // For starting session in advance via lock icon tap
  Set<String> _completedSlotIds =
      {}; // Slots that have already had a session completed
  final Set<String> _failedSlotIds =
      {}; // Subset of completed slots where the session failed
  bool _isKeypadExpanded = false; // Controls OTP keypad expansion state

  // Session ID received from the preflight API response (_triggerWarmUp).
  // Stored here in RAM so OTP submission (_handleVerifyOtp) can use it
  // directly. Falls back to initiateSession() API response if this is null.
  String? _preAllocatedSessionId;
  PreFlightStatus _preFlightStatus = PreFlightStatus.none;
  String? _preFlightError;
  bool _isReadyCheckDone = false;

  /// Tracks which upcoming slot's warm-up has been initiated so the 10-second
  /// [_preClassTimer] in [_checkUpcomingClass] does NOT re-trigger a warm-up
  /// that already failed. Without this guard, the UI cycles through
  /// PENDING → WARMING UP... → PENDING → WARMING UP... every 10 seconds.
  String? _warmUpTriggeredSlotId;

  /// Holds the pre-allocated session ID received from a T-3 warm-up for the
  /// UPCOMING class. Kept separate from [_preAllocatedSessionId] so that a
  /// background warm-up for the upcoming class does not overwrite the current
  /// class's armed state. Used by [_handleVerifyOtp] when the upcoming class
  /// becomes the active target.
  String? _upcomingAllocatedSessionId;

  StreamSubscription<dynamic>?
      _preFlightSessionSubscription; // cleanup handle for warm-up

  /// Tracks the last active slot ID so we can detect slot transitions
  /// and reset warm-up state for the new slot.
  String? _lastBedrockSlotId;

  // Tracks which slots have already triggered a Kiosk restore at T-0 so the
  // 10s timer does not spam KioskService.setMode on every tick.
  final Set<String> _t0RestoredSlots = {};

  bool _isUpcomingClassCheckRunning = false;

  /// Tracks which slots have completed warm-up successfully.
  /// Cleared only on slot transitions — prevents the 10-second timer from
  /// re-triggering warm-up when [_preFlightStatus] is transiently `connecting`.
  final Set<String> _completedWarmUpSlots = {};

  /// Monotonic clock started at warm-up time. Combined with [_serverWarmUpTime]
  /// to provide a server-corrected time that never jumps backwards.
  Stopwatch? _monotonicWarmUpClock;

  /// Server time (epoch ms) captured from the last successful warm-up response.
  DateTime? _serverWarmUpTime;

  /// 2-minute hard cooldown state machine between classes.
  /// Prevents class-overlap data contamination and provides a clean boundary.
  CooldownState _cooldownState = CooldownState.none;
  int _cooldownSecondsRemaining = 120;
  Timer? _cooldownTimer;

  // Listens to the global TimetableCache — every Firestore snapshot update
  // triggers _onTimetableCacheChanged which re-reads today's entries from RAM
  // and calls setState, keeping the entire idle UI in sync without polling.
  DateTime? _lastCacheUpdate;
  void _onTimetableCacheChanged() {
    final now = DateTime.now();
    if (_lastCacheUpdate != null &&
        now.difference(_lastCacheUpdate!).inMilliseconds < 1000) {
      return;
    }
    _lastCacheUpdate = now;
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
    );

    // Load timetable from Isar + subscribe to in-memory cache for live updates.
    // The cache is the single source of truth for the current slot — the local
    // _findCurrentSlot is removed in favour of TimetableCache().currentSlot.
    _loadInitialData(); // Isar read — local only, safe.
    _loadPreferences(); // SecureStorage read — local only, safe.

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

      // 3. The Firestore listener (or its REST fallback) already synced the
      //    timetable inside startBackgroundProtocols().  We only need to read
      //    from Isar to populate the UI state — no duplicate REST sync.
      await ApiService.syncTime().catchError((_) {
        Log.w('[Idle] Boot time sync failed — using cached skew.');
        return 0;
      });

      await _refreshTimetable();
      _checkCrashRecovery();
      // Load completed slots before starting the 10s timer so the first
      // _checkUpcomingClass() tick sees accurate data. Without this, a
      // release-build AOT race (debug JIT overhead hides it) leaves the
      // set empty, causing warm-up + OTP card to show for completed slots.
      await _loadCompletedSlots();
      _startPreClassTimer();
      _startCinematicMonitor();
      if (AppConfig.enableVideoBreaks) {
        _initVideoBackground();
      }

      // 4. If returning from a completed attendance session, show COMPLETED
      //    status for 3 seconds then auto-minimize to the OS desktop.
      if (widget.completedSession) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        await KioskService.setMode(KioskMode.suspended);
      }
    });
  }

  void _startCinematicMonitor() {
    _cinematicTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final isBreak = _isAnyBreak();
      final hasVideo =
          isBreak && _isVideoInitialized && _videoController != null;

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
        _breakStartedAt = TimeSyncService.timeNow;
        _cinematicController.reverse();
      }

      // After 3 minutes (Production Logic), transition to Dark (1.0)
      final elapsedMinutes =
          TimeSyncService.timeNow.difference(_breakStartedAt!).inMinutes;
      if (elapsedMinutes >= 3 &&
          !_isCinematicTransitionTriggered &&
          !_showStartingSoon) {
        _isCinematicTransitionTriggered = true;
        _cinematicController.forward();
      }

      // 3 minutes before next class, transition back to White (0.0)
      if (_showStartingSoon &&
          _cinematicController.value > 0 &&
          _cinematicController.status != AnimationStatus.reverse) {
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
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(AppConfig.ambientVideoUrl),
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
      ..sort(
          (a, b) => _toMinutes(a.startTime).compareTo(_toMinutes(b.startTime)));
    for (int i = 0; i < sorted.length - 1; i++) {
      final prevEnd = _toMinutes(sorted[i].endTime);
      final nextStart = _toMinutes(sorted[i + 1].startTime);
      int gap = nextStart - prevEnd;
      if (gap < _midnightWrapThreshold) gap += _minutesPerDay;
      if (gap >= 5 && nowMinutes >= prevEnd && nowMinutes < nextStart)
        return gap;
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
    if (diff < _midnightWrapThreshold) diff += _minutesPerDay;
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
    await _loadCompletedSlots();
  }

  Future<void> _loadCompletedSlots() async {
    final completed = await SessionManager.getCompletedSlotIds();
    if (mounted) {
      setState(() => _completedSlotIds = completed);
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
    _cooldownTimer?.cancel();
    _preFlightSessionSubscription?.cancel();
    _cinematicController.dispose();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _forceShowCard && _bedrockEntry == null && !_showStartingSoon) {
        setState(() {
          _forceShowCard = false;
          _isKeypadExpanded = false;
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
  /// If one exists (e.g. the board crashed mid-session), clears it to prevent
  /// auto-navigation to locked mode without OTP entry. The faculty member
  /// must enter the OTP fresh to start a new session.
  Future<void> _checkCrashRecovery() async {
    try {
      final session = await SessionManager.getResumeableSession();
      if (session == null) return;

      Log.w(
          '[Idle] Found stale session ${session.sessionId} — clearing to prevent auto-lock without OTP.');
      await SessionManager.clearSession(session.sessionId);
      try {
        await SecureStorageService.deleteSessionSecret(session.sessionId);
      } catch (e) {
        Log.d('[Idle] Could not delete stale session secret: $e');
      }
      Log.i('[Idle] Stale session cleared safely.');
    } catch (e) {
      Log.w('⚠️ [Idle] Crash recovery cleanup failed: $e');
    }
  }

  /// Helper to derive the final secret using the hardware fingerprint (Atomic Logic)
  Future<String?> _deriveSecret(Map<String, dynamic> data) async {
    try {
      final half1 = data['session_secret_half1']?.toString();
      if (half1 == null) return null;

      final deviceId = await HardwareFingerprintService.getDeviceId();
      final half2 = Hmac(sha256, utf8.encode(deviceId))
          .convert(utf8.encode(half1))
          .toString()
          .substring(0, 16);
      return '$half1$half2';
    } catch (e) {
      Log.e('[Idle] Secret derivation failed: $e');
      return null;
    }
  }

  void _startPreClassTimer() {
    _preClassTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {
          _bedrockEntry = TimetableCache().currentSlot;
        });
      }
      Log.iThrottled('idle_timer_tick',
          '[IdleTimer] tick: bedrockEntry.slotId=${_bedrockEntry?.slotId}  timelineCount=${TimetableCache().todayTimeline.length}  now=${TimeSyncService.timeNow.hour}:${TimeSyncService.timeNow.minute}');
      if (!_isUpcomingClassCheckRunning) {
        _isUpcomingClassCheckRunning = true;
        try {
          _checkUpcomingClass();
        } finally {
          _isUpcomingClassCheckRunning = false;
        }
      }
      _checkDayChange();
    });
    _checkUpcomingClass();
  }

  int? _lastQueryDay;
  void _checkDayChange() {
    final today = TimeSyncService.timeNow.weekday;
    if (_lastQueryDay != null && _lastQueryDay != today) {
      Log.i(
          '📅 [Idle] Day changed from $_lastQueryDay to $today. Refreshing from cache...');
      _lastQueryDay = today;
      _t0RestoredSlots.clear();
      _preAllocatedSessionId = null;
      _upcomingAllocatedSessionId = null;
      _warmUpTriggeredSlotId = null;
      _preFlightStatus = PreFlightStatus.none;
      _preFlightError = null;
      _lastBedrockSlotId = null;
      _refreshTimetable();
      SessionManager.clearCompletedSessionsForDay(_lastQueryDay!);
      _loadCompletedSlots();
    }
    _lastQueryDay ??= today;
  }

  void _checkUpcomingClass() {
    if (_todayTimeline.isEmpty) return;

    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;

    // ── Slot Transition Detection ─────────────────────────────────────────
    // When the active slot changes (e.g. P2 ends, P3 begins), reset warm-up
    // state for the new slot so it gets a fresh retry budget. This also
    // fires on first load after boot (null → first slot).
    //
    // Also fires when a class ends (non-null → null) to clean up the OTP
    // card and session state so the screen returns to the ambient idle view
    // during lunch breaks or gaps between classes.
    final bedrockSlotId = _bedrockEntry?.slotId;
    if (bedrockSlotId != null && bedrockSlotId != _lastBedrockSlotId) {
      Log.i(
          '[Idle] Slot transition detected: $_lastBedrockSlotId → $bedrockSlotId');

      // Step 1: Transfer any T-3 session to current class BEFORE clearing
      // tracking registers. This prevents a successful T-3 warm-up from being
      // dropped when the slot boundary crosses T-0.
      if (_preAllocatedSessionId == null &&
          _upcomingAllocatedSessionId != null &&
          _upcomingSlot?.slotId == bedrockSlotId) {
        _preAllocatedSessionId = _upcomingAllocatedSessionId;
        _upcomingAllocatedSessionId = null;
        _preFlightStatus = PreFlightStatus.ready;
        _completedWarmUpSlots.add(bedrockSlotId);
        Log.i('[Idle] Transferred T-3 session to current slot $bedrockSlotId during transition.');
      }

      // Step 2: Reset tracking registers for the NEXT upcoming class.
      // This runs after the transfer so the guard at T-0 warm-up check sees
      // _preAllocatedSessionId != null and does NOT re-trigger warm-up.
      PreFlightService().resetForSlot(bedrockSlotId);
      _lastBedrockSlotId = bedrockSlotId;
      _warmUpTriggeredSlotId = null;
      _completedWarmUpSlots.clear();
      _preFlightError = null;
      _forceShowCard = false;
      _isReadyCheckDone = false;

      // Step 3: If no session was transferred, enter PENDING state so the
      // OTP card shows "PENDING" instead of silently staying at none.
      if (_preAllocatedSessionId == null) {
        _upcomingAllocatedSessionId = null;
        _preFlightStatus = PreFlightStatus.pending;
      }
    }
    if (bedrockSlotId == null && _lastBedrockSlotId != null) {
      Log.i('[Idle] Class ended: $_lastBedrockSlotId → (break).');

      // Immediate cleanup: subscriptions + service state.
      final endedSlotId = _lastBedrockSlotId!;
      PreFlightService().resetForSlot('');
      _lastBedrockSlotId = null;
      _preFlightSessionSubscription?.cancel();

      // Start 2-minute hard cooldown only if attendance was NOT taken.
      // If attendance WAS taken, skip the freeze — the next 10s tick handles
      // the transition naturally. The _cooldownState guard also prevents
      // double-firing if T-5 already started the cooldown proactively.
      if (!widget.completedSession && _cooldownState == CooldownState.none) {
        if (!WindowOrchestratorService().hasTakenAttendance(endedSlotId)) {
          _startCooldown();
        }
      }
    }
    if (bedrockSlotId == null) {
      _lastBedrockSlotId = null;
    }

    // ── Next upcoming class ───────────────────────────────────────────────────
    // Computed early so both T-5 cooldown and T-3 warm-up can reference it.
    TimetableEntry? nextEntry;
    int minDiff = 9999;

    for (final entry in _todayTimeline) {
      final parts = entry.startTime.split(':');
      if (parts.length != 2) continue;

      int entryMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      int diff = entryMinutes - currentMinutes;

      if (diff < _midnightWrapThreshold) {
        diff += _minutesPerDay;
      }

      if (diff > 0 && diff < minDiff) {
        minDiff = diff;
        nextEntry = entry;
      }
    }

    // ── T-5 proactive cooldown ──────────────────────────────────────────────
    // If the current class is within 5 minutes of its scheduled end time and
    // attendance has NOT been taken locally, start the 2-minute hard cooldown
    // immediately. This guarantees the freeze completes BEFORE the next class's
    // T-3 window (e.g., 09:55-09:57 for a 10:00 class), eliminating the
    // back-to-back overlap trap where the cooldown would otherwise block the
    // incoming class's T-0.
    //
    // Guard: if _preAllocatedSessionId is non-null, the user may be mid-OTP-
    // entry on the IdleScreen card. We skip the proactive cooldown and let the
    // natural class-end handler (line 582) decide.
    //
    // Also skip if _upcomingAllocatedSessionId is non-null — the T-3 warm-up
    // already succeeded for the next class; starting a cooldown would wipe
    // that pre-allocated session and force a redundant re-warm-up cycle.
    //
    // Also skip when minDiff <= 3 — the next class T-3 window is active or
    // imminent; the cooldown would block the warm-up and create a loop.
    if (_bedrockEntry != null &&
        _cooldownState != CooldownState.locked &&
        _preAllocatedSessionId == null &&
        _upcomingAllocatedSessionId == null &&
        minDiff > 3) {
      final endParts = _bedrockEntry!.endTime.split(':');
      if (endParts.length == 2) {
        final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
        final diffToEnd = endMinutes - currentMinutes;
        if (diffToEnd <= 5 && diffToEnd > 0) {
          final slotId = _bedrockEntry!.slotId;
          if (!WindowOrchestratorService().hasTakenAttendance(slotId)) {
            Log.w('[Idle] T-5 proactive cooldown for slot $slotId — attendance not taken.');
            _startCooldown();
            return;
          }
        }
      }
    }

    // ── Cooldown guard ─────────────────────────────────────────────────────
    // During the 2-minute hard freeze, all T-3/T-0 processing is skipped.
    // After cooldown completes, _evaluateNextClass handles the next-link chain.
    if (_cooldownState == CooldownState.locked) return;

    // ── Current Class State ───────────────────────────────────────────────────
    // Manages the OTP card visibility and session transfer for the active class.
    // Warm-up at T-3 is handled exclusively by the upcoming-class block below.
    if (_bedrockEntry != null) {
      final currentSlotId = _bedrockEntry!.slotId;
      final isBedrockCompleted = _completedSlotIds.contains(currentSlotId);
      if (isBedrockCompleted) {
        Log.iOnce('completed_$currentSlotId',
            '[Idle] Current slot $currentSlotId already completed — skipping auto-show and warm-up.');
        setState(() {
          _preAllocatedSessionId = null;
          _preFlightStatus = PreFlightStatus.none;
          _forceShowCard = false;
        });
      } else {
        if (!_forceShowCard && mounted) {
          setState(() {
            _forceShowCard = true;
          });
        }

        // Transfer T-3 pre-allocated session to current class if the upcoming
        // class (which was warmed up) is now the active class. This prevents
        // the cleanup (minDiff > 5) from losing the session ID.
        if (_upcomingAllocatedSessionId != null &&
            _upcomingSlot?.slotId == currentSlotId) {
          setState(() {
            _preAllocatedSessionId = _upcomingAllocatedSessionId;
            _upcomingAllocatedSessionId = null;
            _preFlightStatus = PreFlightStatus.ready;
          });
          Log.i(
              '[Idle] Transferred T-3 session to current class $currentSlotId');
        }

        if (!_t0RestoredSlots.contains(currentSlotId)) {
          _t0RestoredSlots.add(currentSlotId);
          KioskService.setMode(KioskMode.fullscreen);
          Log.i(
              '[Idle] T-0 restore: slot $currentSlotId — window brought to foreground.');
        }

        // One-time fallback warm-up if T-3 was missed (e.g. app started
        // during an active class). Guards: no session yet, not already in
        // progress, not already completed for this slot, retries remain.
        if (_preAllocatedSessionId == null &&
            _preFlightStatus != PreFlightStatus.connecting &&
            !_completedWarmUpSlots.contains(currentSlotId) &&
            !PreFlightService().isWarmUpExhausted(currentSlotId)) {
          Log.i(
              '[Idle] Current class $currentSlotId in session — triggering warm-up.');
          _triggerWarmUp(currentSlotId);
        }

        if (_preAllocatedSessionId == null &&
            _preFlightStatus != PreFlightStatus.ready &&
            _preFlightStatus != PreFlightStatus.connecting &&
            !PreFlightService().isWarmUpExhausted(currentSlotId)) {
          setState(() {
            _errorMessage = 'System sync delayed. Enter PIN to proceed.';
          });
        }
      }
    }

    // ── Upcoming Class (T-3 window) ─────────────────────────────────────────
    if (nextEntry != null && minDiff <= 3) {
      final isCompleted = _completedSlotIds.contains(nextEntry.slotId);
      if (mounted) {
        setState(() {
          _upcomingSlot = nextEntry;
          _showStartingSoon = !isCompleted;
        });

        if (isCompleted) {
          Log.iOnce('completed_${nextEntry.slotId}',
              '[Idle] Slot ${nextEntry.slotId} already completed — skipping warm-up and OTP.');
          return;
        }

        if (_warmUpTriggeredSlotId != nextEntry.slotId &&
            !PreFlightService().isWarmUpExhausted(nextEntry.slotId)) {
          _warmUpTriggeredSlotId = nextEntry.slotId;
          _triggerWarmUp(nextEntry.slotId);
        }

        if (minDiff == 1 && !_isReadyCheckDone) {
          _isReadyCheckDone = true;
          ApiService.syncReadyCheck()
              .catchError((e) => Log.w('⚠️ Ready check failed: $e'));
        }
      }
    } else {
      _isReadyCheckDone = false;

      if (nextEntry != null && minDiff <= 10) {
        final bool isFirstClass = _todayTimeline.isNotEmpty &&
            _todayTimeline.first.slotId == nextEntry.slotId;
        if (isFirstClass) {
          PreFlightService().runDailyBoot();
        }
      }

      if (mounted && minDiff > 5 && _bedrockEntry == null) {
        final shouldReset = _preFlightStatus != PreFlightStatus.ready &&
            _preFlightStatus != PreFlightStatus.connecting &&
            _preFlightStatus != PreFlightStatus.pending;
        if (shouldReset) {
          setState(() {
            _showStartingSoon = false;
            _isKeypadExpanded = false;
            _upcomingSlot = null;
            _preFlightStatus = PreFlightStatus.none;
            _preFlightError = null;
            _forceShowCard = false;
            _warmUpTriggeredSlotId = null;
            _preFlightSessionSubscription?.cancel();
            _preAllocatedSessionId = null;
            _upcomingAllocatedSessionId = null;
          });
        }
      }
    }
  }

  // ── 2-Minute Hard Cooldown ────────────────────────────────────────────────

  /// Enters the locked cooldown state and starts a 120-second countdown.
  /// The cooldown prevents class-overlap data contamination by deferring
  /// the full cache cleanse to [_onCooldownComplete].
  void _startCooldown() {
    _cooldownState = CooldownState.locked;
    _cooldownSecondsRemaining = 120;
    _forceShowCard = false;
    _isKeypadExpanded = false;
    _otpController.clear();
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _cooldownSecondsRemaining--;
      if (_cooldownSecondsRemaining <= 0) {
        _cooldownTimer?.cancel();
        _onCooldownComplete();
      }
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
    Log.i('[Idle] 2-min cooldown started.');
  }

  /// Called when the 120-second cooldown expires.
  /// Performs full cache cleanse then immediately evaluates the next class.
  void _onCooldownComplete() {
    _fullCleanup();
    _evaluateNextClass();
    if (mounted) setState(() {});
    Log.i('[Idle] Cooldown complete. Cache cleansed, next-link evaluated.');
  }

  /// Full cache cleanse — wipes all warm-up state, session IDs, and tracking
  /// registers so the next class starts with a clean slate.
  void _fullCleanup() {
    _warmUpTriggeredSlotId = null;
    _completedWarmUpSlots.clear();
    _preFlightStatus = PreFlightStatus.none;
    _preFlightError = null;
    _forceShowCard = false;
    _showStartingSoon = false;
    _isKeypadExpanded = false;
    _upcomingSlot = null;
    _preAllocatedSessionId = null;
    _upcomingAllocatedSessionId = null;
    _cooldownState = CooldownState.none;
    _otpController.clear();
  }

  /// Evaluates the next upcoming class after cooldown and immediately enters
  /// the T-3 window if within range (next-link chaining).
  void _evaluateNextClass() {
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
      if (diff < _midnightWrapThreshold) diff += _minutesPerDay;
      if (diff > 0 && diff < minDiff) {
        minDiff = diff;
        nextEntry = entry;
      }
    }

    if (nextEntry == null) return;
    Log.i('[Idle] Next-link: next class "${nextEntry.courseName}" starts in $minDiff min.');

    // T-10 daily boot (first class only)
    if (minDiff <= 10) {
      final bool isFirstClass = _todayTimeline.isNotEmpty &&
          _todayTimeline.first.slotId == nextEntry.slotId;
      if (isFirstClass) {
        PreFlightService().runDailyBoot();
      }
    }

    // T-3 window: set up upcoming slot and trigger warm-up immediately
    if (minDiff <= 3 && !_completedSlotIds.contains(nextEntry.slotId)) {
      _upcomingSlot = nextEntry;
      _showStartingSoon = true;
      if (!PreFlightService().isWarmUpExhausted(nextEntry.slotId)) {
        _warmUpTriggeredSlotId = nextEntry.slotId;
        _triggerWarmUp(nextEntry.slotId);
      }
      Log.i('[Idle] Next-link: entering T-3 window for slot ${nextEntry.slotId}.');
    }
  }

  void _triggerWarmUp(String slotId, {bool force = false}) async {
    final isForUpcoming =
        slotId == _upcomingSlot?.slotId && slotId != _bedrockEntry?.slotId;
    final currentId = _bedrockEntry?.slotId;
    final upcomingId = _upcomingSlot?.slotId;

    try {
      setState(() {
        _preFlightStatus = PreFlightStatus.connecting;
        _preFlightError = null;
        _errorMessage = null;
      });

      void onWarmUpSuccess(Map<String, dynamic> result) {
        if (!mounted) {
          Log.d('[Idle] onWarmUpSuccess: not mounted — skipping');
          return;
        }

        Log.d('[Idle] onWarmUpSuccess fired for slot=$slotId current=$currentId upcoming=$upcomingId keys=[${result.keys.join(", ")}]');

        if (slotId != currentId && slotId != upcomingId) {
          Log.w(
              '⚠️ [Idle] Ignoring stale warm-up success for $slotId (current=$currentId upcoming=$upcomingId)');
          return;
        }

        final sessionId = result['session_id']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          final pid = sessionId;

          // Mark this slot as completed so the 10-second timer stops
          // re-triggering warm-up.
          _completedWarmUpSlots.add(slotId);

          // Capture server time and start a monotonic reference clock.
          // This gives us a server-corrected time that never jumps backwards
          // (unlike wall-clock-based drift correction).
          final serverTs =
              (result['server_timestamp'] ?? result['server_timestamp_ms'] ?? 0)
                  as int;
          if (serverTs > 0) {
            _serverWarmUpTime = DateTime.fromMillisecondsSinceEpoch(serverTs);
            (_monotonicWarmUpClock ??= Stopwatch()).start();
          }

          if (isForUpcoming) {
            setState(() {
              _upcomingAllocatedSessionId = pid;
              _preFlightStatus = PreFlightStatus.ready;
              _preFlightError = null;
              _errorMessage = null;
            });
            Log.i('✅ [Idle] UPCOMING class armed. SessionID: $pid.');
          } else {
            setState(() {
              _preFlightStatus = PreFlightStatus.ready;
              _preAllocatedSessionId = pid;
              _preFlightError = null;
              _errorMessage = null;
            });
            Log.i('✅ [Idle] Board ARMED. SessionID in RAM: $pid.');
          }
        } else {
          Log.d('[Idle] Warm-up response missing session_id. Keys: ${result.keys.join(", ")}');
          Log.d('[Idle] Full response: $result');
          setState(() {
            if (isForUpcoming) {
              _upcomingAllocatedSessionId = null;
            } else {
              _preAllocatedSessionId = null;
            }
          });
        }
      }

      void onStatusChange(String status) {
        if (!mounted) return;

        if (slotId != currentId && slotId != upcomingId) return;

        setState(() {
          if (status == 'connecting') {
            _preFlightStatus = PreFlightStatus.connecting;
          } else if (status == 'none') {
            _preFlightStatus = PreFlightStatus.none;
          }
        });
      }

      void onWarmUpError(String error) {
        if (!mounted) return;
        if (slotId != currentId && slotId != upcomingId) return;

        setState(() {
          _preFlightStatus = PreFlightStatus.none;
          _preFlightError = 'Warm-up failed: $error';
        });
        Log.w('[Idle] Pre-flight warm-up error: $error');
      }

      await (force
          ? PreFlightService().forceWarmUp(slotId,
              onSuccess: onWarmUpSuccess,
              onStatusChange: onStatusChange,
              onError: onWarmUpError)
          : PreFlightService().runPerSessionWarmUp(slotId,
              onSuccess: onWarmUpSuccess,
              onStatusChange: onStatusChange,
              onError: onWarmUpError));
    } catch (e) {
      if (mounted) {
        if (e is UnregisteredException) {
          Log.w(
              '🚨 [IdleScreen] Pre-flight failed: Device unregistered. Redirecting...');
          await context.read<IDeviceRepository>().clearRegistration();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const RegistrationScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _preFlightStatus = PreFlightStatus.none;
            _preFlightError = 'Pre-flight failed: $e';
          });
          Log.w(
              '⚠️ [Idle] Pre-flight failed. Faculty may still proceed manually: $e');
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
    if (_preAllocatedSessionId == null && _upcomingAllocatedSessionId == null) {
      if (_upcomingSlot != null) {
        _triggerWarmUp(_upcomingSlot!.slotId, force: true);
      }
      if (_preAllocatedSessionId == null &&
          _upcomingAllocatedSessionId == null) {
        Log.w(
            '[Idle] Pre-flight unavailable. Faculty may proceed with API-provided session ID.');
      }
    }

    final rateKey = 'session_pin_${widget.registration.smartBoardId}';
    if (!RateLimiter.isAllowed(rateKey)) {
      setState(() => _errorMessage =
          'Too many attempts. Please wait before trying again.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Strict OTP Protocol: OTP must never be stored. The text controller is
      // cleared the instant the API call fires — before waiting for a response.
      _otpController.clear();

      final result = await ApiService.initiateSession(otp);
      RateLimiter.reset(rateKey);
      final data = result['data'] ?? result;

      // Pre-allocated session ID from warm-up is authoritative if available.
      // Fall back to the API response when retries were exhausted.
      final sessionId = _preAllocatedSessionId ??
          _upcomingAllocatedSessionId ??
          data['session_id']?.toString();

      final sessionSecret = await _deriveSecret(data);

      final rosterCount = data['roster_count'] is int
          ? data['roster_count']
          : int.tryParse(data['roster_count']?.toString() ?? '0') ?? 0;
      final facultyName = data['faculty_name']?.toString() ?? 'Professor';
      final courseName = data['course_name']?.toString() ?? 'Active Class';
      final sectionId =
          data['section_id']?.toString() ?? widget.registration.smartBoardId;
      final accessToken = data['access_token']?.toString();

      if (sessionId == null || sessionSecret == null) {
        setState(() => _errorMessage =
            'Invalid server response: missing session data. Please try again with a new PIN.');
        return;
      }

      final slotId = _upcomingSlot?.slotId ?? _bedrockEntry?.slotId;

      await SessionManager.saveSession(
        sessionId: sessionId,
        rosterCount: rosterCount,
        facultyName: facultyName,
        courseName: courseName,
        sectionId: sectionId,
        endTime: TimeSyncService.timeNow.add(const Duration(hours: 1)),
      );

      // Persist a CompletedSession record immediately so the slot is marked
      // as attended even if the app is killed mid-QR-rotation. Prevents a
      // second OTP entry for the same slot on restart. The actual attendee
      // count is updated when SummaryScreen._persistCompletedSession runs.
      if (slotId != null) {
        await SessionManager.recordCompletedSession(
          slotId: slotId,
          sessionId: sessionId,
          courseName: courseName,
          facultyName: facultyName,
          attendeeCount: 0,
        );
        WindowOrchestratorService().markAttendanceTaken(slotId);
      }

      MetricsCollector().recordSessionStart();
      await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);

      // Session is now live — clear the in-memory pre-allocated IDs so they
      // cannot be accidentally reused if the board returns to IdleScreen.
      if (mounted) setState(() {
        _preAllocatedSessionId = null;
        _upcomingAllocatedSessionId = null;
      });

      if (mounted) {
        final engine = TotpEngine(
          sessionId: sessionId,
          sessionSecret: sessionSecret,
        );
        final wsService = WebsocketService(AppConfig.baseUrl);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AttendanceScreen(
              sessionId: sessionId,
              totpEngine: engine,
              websocketService: wsService,
              accessToken: accessToken ?? '',
              capacity: widget.registration.capacity,
              courseName: courseName,
              facultyName: facultyName,
              sectionId: sectionId,
              roomName: widget.registration.roomName,
              slotId: slotId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is UnregisteredException) {
          Log.w(
              '🚨 [IdleScreen] Device unregistered on server. Redirecting to Registration...');
          await context.read<IDeviceRepository>().clearRegistration();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const RegistrationScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() =>
              _errorMessage = e.toString().replaceFirst('Exception: ', ''));
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
    final showVideo =
        isBreak && _isVideoInitialized && _videoController != null;

    // Theme Calculation Logic:
    // If showVideo is false OR session is being initiated (forceShowCard), we are "Blindly White"
    final bool isBlindlyWhite = !showVideo || _forceShowCard;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _cinematicController,
        builder: (context, _) {
          final morph = isBlindlyWhite ? 0.0 : _cinematicController.value;

          final overlayColor = Color.lerp(Colors.white.withValues(alpha: 0.1),
              Colors.black.withValues(alpha: 0.4), morph)!;

          final headerFooterColor =
              Color.lerp(Colors.white, AppColors.bgDark, morph)!;

          final primaryTextColor =
              Color.lerp(AppColors.textPrimaryLight, Colors.white, morph)!;

          final secondaryTextColor = Color.lerp(
              AppColors.textSecondaryLight, AppColors.textSecondaryDark, morph)!;

          final isBedrockCompleted =
              _bedrockEntry != null && _completedSlotIds.contains(_bedrockEntry!.slotId);
          final bool showCardContextually = (_forceShowCard || _bedrockEntry != null) &&
              _cooldownState != CooldownState.locked &&
              !isBedrockCompleted;

          final cardOpacity = showCardContextually ? 1.0 : 0.0;
          final lockOpacity = showCardContextually ? 0.0 : 1.0;

          List<Widget> stackChildren = [];

          // 1. Background
          if (showVideo) {
            stackChildren.add(SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ));
          } else {
            stackChildren.add(
                Container(color: isDark ? AppColors.bgDark : AppColors.bgLight));
          }

          // 2. Overlay
          if (showVideo) {
            stackChildren.add(
                Container(decoration: BoxDecoration(color: overlayColor)));
          }

          // 3. Logo
          if (!showVideo) {
            stackChildren.add(Opacity(
              opacity: isDark ? 0.05 : 0.03,
              child: Center(
                child: Image.asset(
                  'assets/background.png',
                  width: size.width * 0.6,
                  fit: BoxFit.contain,
                ),
              ),
            ));
          }

          // 4. Main UI
          stackChildren.add(Column(
            children: [
              _buildTopHeader(primaryTextColor, headerFooterColor, showVideo),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 80),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildCourseInfo(
                            primaryTextColor, secondaryTextColor, showVideo),
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
                                      isBlindlyWhite
                                          ? Colors.white
                                          : headerFooterColor,
                                      isBlindlyWhite
                                          ? AppColors.textPrimaryLight
                                          : primaryTextColor,
                                      isBlindlyWhite
                                          ? AppColors.textSecondaryLight
                                          : secondaryTextColor,
                                      showVideo && !isBlindlyWhite),
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
              _buildFooter(
                  headerFooterColor, primaryTextColor, secondaryTextColor,
                  showVideo),
            ],
          ));

          // 5. Banner
          if (_showStartingSoon && _upcomingSlot != null) {
            stackChildren.add(_buildStartingSoonBanner());
          }

          return Stack(children: stackChildren);
        },
      ),
    );
  }

  Widget _buildTopHeader(Color textColor, Color bgColor, bool isVideoActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.8),
        border:
            Border(bottom: BorderSide(color: textColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo_square.png',
            width: 36,
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Text(
            'IntelliAttend SmartBoard',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textColor == Colors.white
                  ? Colors.white
                  : AppColors.primaryTeal,
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
      case PreFlightStatus.none:
        return 'PENDING';
      case PreFlightStatus.connecting:
        return 'WARMING UP...';
      case PreFlightStatus.ready:
        return 'READY';
      case PreFlightStatus.pending:
        return 'PENDING';
    }
  }

  Color _getIndicatorColor() {
    return _preFlightStatus == PreFlightStatus.ready
        ? AppColors.successLime
        : AppColors.primaryTeal;
  }

  /// Returns a server-corrected monotonic time by adding the elapsed time
  /// since warm-up to the server's timestamp. Falls back to [TimeSyncService]
  /// if no warm-up has completed yet.
  DateTime get _warmUpServerTime {
    if (_serverWarmUpTime != null && (_monotonicWarmUpClock?.isRunning ?? false)) {
      return _serverWarmUpTime!.add(_monotonicWarmUpClock!.elapsed);
    }
    return TimeSyncService.timeNow;
  }

  Widget _buildNavLinks(Color color) {
    final activeColor =
        color == Colors.white ? Colors.white : AppColors.primaryTeal;
    final inactiveColor =
        color == Colors.white ? Colors.white70 : AppColors.textSecondaryLight;

    return Row(
      children: [
        _navItem('Welcome', activeColor, true, () {}),
        const SizedBox(width: 30),
        _navItem('Timetable', inactiveColor, false, () {
          final weekly = TimetableCache().weeklyTimeline;
          Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => TimetableScreen(weeklyTimeline: weekly)));
        }),
        const SizedBox(width: 30),
        _navItem('Analytics', inactiveColor, false, () {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()));
        }),
      ],
    );
  }

  Widget _navItem(
      String label, Color color, bool isActive, VoidCallback onTap) {
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
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const NotificationsScreen()));
            },
            icon: Icon(Icons.notifications_none, color: iconColor)),
        IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('IntelliAttend Support: Help is on the way!')));
            },
            icon: Icon(Icons.help_outline, color: iconColor)),
        IconButton(
          onPressed: () => KioskService.setMode(KioskMode.suspended),
          icon: Icon(Icons.minimize_rounded, color: iconColor),
          tooltip: 'Minimize to Desktop',
        ),
        IconButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) =>
                      SettingsScreen(registration: widget.registration)));
              _loadPreferences();
            },
            icon: Icon(Icons.settings_outlined, color: iconColor)),
      ],
    );
  }

  Widget _buildCourseInfo(
      Color primaryColor, Color secondaryColor, bool isVideoActive) {
    final isSunday = TimeSyncService.timeNow.weekday == DateTime.sunday;
    final isBio = _isBioBreak();
    final isLunch = _isLunchBreak();
    final hasBreak = isBio || isLunch;

    var course = _bedrockEntry?.courseName ?? '';
    var faculty = _bedrockEntry?.facultyName ?? '';

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
    } else if (_bedrockEntry == null && _upcomingSlot != null) {
      // Between classes: show the next class info instead of "NO ACTIVE SESSION"
      course = 'UP NEXT: ${_upcomingSlot!.courseName}';
      faculty = _upcomingSlot!.facultyName;
    } else if (_bedrockEntry == null) {
      course = 'NO ACTIVE SESSION';
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
                  color: primaryColor == Colors.white
                      ? AppColors.surfaceDark
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Icon(Icons.school_outlined,
                    color: AppColors.primaryTeal),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (faculty.contains('@')
                        ? faculty
                            .split('@')[0]
                            .replaceAll('_', ' ')
                            .toUpperCase()
                        : faculty.toUpperCase()),
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
                child: Icon(
                    isBio ? Icons.coffee_outlined : Icons.restaurant_outlined,
                    color: AppColors.primaryTeal),
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

  Widget _buildAuthCard(Color bgColor, Color primaryColor, Color secondaryColor,
      bool isVideoActive) {
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
              Icon(Icons.lock_open_outlined,
                  size: 20, color: secondaryColor.withValues(alpha: 0.5)),
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
            onTap: () {
              setState(() => _isKeypadExpanded = !_isKeypadExpanded);
              _resetInactivityTimer();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: PinInput(
                value: _otpController.text,
                obscureText: true,
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _buildNumericKeypad(
                  primaryColor == Colors.white, isVideoActive),
            ),
            crossFadeState: _isKeypadExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
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
          if (_preFlightError != null && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _preFlightError!,
                  style: TextStyle(
                    color: AppColors.warningAmber,
                    fontSize: 10,
                  ),
                  maxLines: 1,
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 10),
                        const Text('SUBMIT',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
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
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: _getIndicatorColor())),
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

  Widget _buildTimelineSlot(int index) {
    final entry = _todayTimeline[index];
    final live = entry.slotId == _bedrockEntry?.slotId;
    Log.iOnChange('timeline_strip_$index', live,
        '[TimelineStrip] idx=$index slot=${entry.slotId} bedrock.slot=${_bedrockEntry?.slotId} isLive=$live');
    final isCompleted = _completedSlotIds.contains(entry.slotId);
    final isFailed = _failedSlotIds.contains(entry.slotId);
    return TimelineSlot(
      entry: entry,
      isLive: live,
      isCompleted: isCompleted,
      isFailed: isFailed,
    );
  }

  Widget _buildFooter(Color bgColor, Color primaryColor, Color secondaryColor,
      bool isVideoActive) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.9),
        border:
            Border(top: BorderSide(color: primaryColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          // Timeline
          Expanded(
            child: _todayTimeline.isEmpty
                ? Center(
                    child: Text(
                      TimeSyncService.timeNow.weekday == DateTime.sunday
                          ? 'SUNDAY FUNDAY'
                          : 'NO CLASSES SCHEDULED TODAY',
                      style: const TextStyle(
                          color: AppColors.textSecondaryDark,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2),
                    ),
                  )
                : Row(
                    children: [
                      for (int i = 0; i < _todayTimeline.length; i++) ...[
                        if (i > 0)
                          Container(
                            width: 1,
                            height: 30,
                            color: secondaryColor.withValues(alpha: 0.1),
                          ),
                        Expanded(
                          child: _buildTimelineSlot(i),
                        ),
                      ],
                    ],
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
      stream: Stream.periodic(
          const Duration(seconds: 1), (_) => TimeSyncService.timeNow),
      builder: (context, snapshot) {
        final now = snapshot.data ?? TimeSyncService.timeNow;
        final timeStr =
            "${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')}";
        final period = now.hour >= 12 ? 'PM' : 'AM';

        return Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room_outlined,
                        size: 16, color: AppColors.primaryTeal),
                    const SizedBox(width: 8),
                    Text(
                      widget.registration.roomName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Capacity: ${widget.registration.capacity}',
                  style: TextStyle(
                    fontSize: 10,
                    color: secondaryColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                height: 40,
                width: 1,
                color: secondaryColor.withValues(alpha: 0.1)),
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${dayNames[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}";
  }

  Widget _buildStartingSoonBanner() {
    return Positioned(
      top: 20,
      left: 0,
      right: 0,
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
    final activeSlotId = _upcomingSlot?.slotId ?? _bedrockEntry?.slotId;
    final isSlotCompleted =
        activeSlotId != null && _completedSlotIds.contains(activeSlotId);
    final isUnlocked = _showStartingSoon && !isSlotCompleted && _upcomingAllocatedSessionId != null;
    final isWiping = _cooldownState == CooldownState.locked;

    String label;
    if (isWiping) {
      final minutes = (_cooldownSecondsRemaining / 60).floor();
      final seconds = _cooldownSecondsRemaining % 60;
      label = 'WIPING SESSION\n${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (isSlotCompleted) {
      label = 'COMPLETED';
    } else if (isUnlocked) {
      label = 'TAP TO START';
    } else {
      label = 'SESSION LOCKED';
    }

    return InkWell(
      onTap: isUnlocked && !isWiping
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
          Stack(
            alignment: Alignment.center,
            children: [
              if (isWiping)
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: _cooldownSecondsRemaining / 120.0,
                    strokeWidth: 3,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.warningAmber),
                    backgroundColor: color.withValues(alpha: 0.1),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSlotCompleted
                      ? AppColors.warningAmber.withValues(alpha: 0.15)
                      : isUnlocked
                          ? AppColors.successLime.withValues(alpha: 0.15)
                          : isWiping
                              ? AppColors.warningAmber.withValues(alpha: 0.1)
                              : color.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSlotCompleted
                        ? AppColors.warningAmber.withValues(alpha: 0.3)
                        : isUnlocked
                            ? AppColors.successLime.withValues(alpha: 0.3)
                            : isWiping
                                ? Colors.transparent
                                : color.withValues(alpha: 0.1),
                  ),
                ),
                child: Icon(
                  isSlotCompleted
                      ? Icons.check_circle_outline
                      : isUnlocked
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                  color: isSlotCompleted
                      ? AppColors.warningAmber
                      : isUnlocked
                          ? AppColors.successLime
                          : isWiping
                              ? AppColors.warningAmber
                              : color.withValues(alpha: 0.5),
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSlotCompleted
                  ? AppColors.warningAmber
                  : isUnlocked
                      ? AppColors.successLime
                      : isWiping
                          ? AppColors.warningAmber
                          : color.withValues(alpha: 0.3),
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
        for (var i = 1; i <= 9; i++)
          _keypadButton(i.toString(), isDark, isVideoActive),
        const SizedBox(),
        _keypadButton('0', isDark, isVideoActive),
        _keypadButton('backspace', isDark, isVideoActive, isAction: true),
      ],
    );
  }

  Widget _keypadButton(String label, bool isDark, bool isVideoActive,
      {bool isAction = false}) {
    return InkWell(
      onTap: () {
        if (label == 'backspace') {
          if (_otpController.text.isNotEmpty) {
            setState(() {
              _otpController.text = _otpController.text
                  .substring(0, _otpController.text.length - 1);
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
          border: Border.all(
              color: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Center(
          child: label == 'backspace'
              ? Icon(Icons.backspace_outlined,
                  size: 16, color: isDark ? Colors.white38 : Colors.black38)
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
