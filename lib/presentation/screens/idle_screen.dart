// Isar-local schedule data, REST-only sync on boot/day-change.
// No Firestore snapshot listeners — zero continuous read cost.

import 'dart:async';
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
import '../../core/security/secure_storage_service.dart';
import '../../core/rate_limiter.dart';
import '../../models/board_notification.dart';
import '../../models/isar_schemas.dart';
import 'package:isar/isar.dart';
import '../widgets/glass_container.dart';
import '../widgets/pin_input.dart';
import '../widgets/timeline_slot.dart';
import '../widgets/notification_bell.dart';
import '../widgets/notification_popdown.dart';
import '../../services/notification_listener_service.dart';
import 'registration_screen.dart';
import 'attendance_screen.dart';
import 'settings_screen.dart';
import 'timetable_screen.dart';
import 'analytics_screen.dart';
import 'notifications_screen.dart';
import 'workspace_screen.dart';
import '../../services/time_sync_service.dart';
import '../../services/timetable_cache.dart';
import '../../services/network_info_service.dart';
import 'package:number_flow/number_flow.dart';
import 'package:video_player/video_player.dart';
import '../../services/pre_flight_service.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/platform/window_orchestrator_service.dart';
import '../../models/media_push_event.dart';
import '../../services/websocket_service.dart';
import '../widgets/media_overlay.dart';

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
  // TEMPORARY: always show minimize button for production safety.
  // Revert by changing back to `false` and restoring the assignments below.
  bool _showMinimizeButton = true;
  bool _showSessionMenu = false;
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

  NetworkInfo _networkInfo = NetworkInfo(isConnected: false, lastChecked: DateTime.now());
  StreamSubscription<NetworkInfo>? _networkSub;

  MediaPushEvent? _activeMediaPush;
  StreamSubscription<MediaPushEvent>? _mediaPushSub;
  StreamSubscription<String>? _mediaClearSub;

  // Session ID received from the preflight API response (_triggerWarmUp).
  // Stored here in RAM so OTP submission (_handleVerifyOtp) can use it
  // directly. Falls back to initiateSession() API response if this is null.
  String? _preAllocatedSessionId;
  PreFlightStatus _preFlightStatus = PreFlightStatus.none;
  String? _preFlightError;
  bool _isReadyCheckDone = false;
  String? _roomNumber;

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

  // Tracks which slots have already triggered cooldown so the 10s timer
  // does not re-enter the T-5 or class-end path after the first 120s cycle.
  final Set<String> _cooldownFiredSlots = {};

  bool _isUpcomingClassCheckRunning = false;

  /// Tracks which slots have completed warm-up successfully.
  /// Cleared only on slot transitions — prevents the 10-second timer from
  /// re-triggering warm-up when [_preFlightStatus] is transiently `connecting`.
  final Set<String> _completedWarmUpSlots = {};

  /// 2-minute hard cooldown state machine between classes.
  /// Prevents class-overlap data contamination and provides a clean boundary.
  CooldownState _cooldownState = CooldownState.none;
  int _cooldownSecondsRemaining = 120;
  Timer? _cooldownTimer;

  /// Break countdown timer for bio/lunch break gaps between classes.
  /// Runs continuously from break start → T-3 → class start.
  /// At T-3 the ring colour transitions from teal → green (same progress).
  int _breakSecondsRemaining = 0;
  int _breakDurationSeconds = 0;
  Timer? _breakTimer;

  /// Tracks whether a session is currently active (has been committed but not ended).
  /// When set, an overlay panel with navigation options is shown on idle screen.
  ActiveSession? _activeSession;

  /// Timestamp when the current session actually started (for progress ring).
  DateTime? _sessionStartTimestamp;

  /// Scheduled end time for the current session (for progress ring).
  DateTime? _sessionScheduledEnd;

  /// Timer that ticks every second to update the session progress ring.
  Timer? _sessionProgressTimer;

  /// Queue of notifications to show as top-sliding popdown banners.
  /// Drained one-by-one; each popdown auto-dismisses before the next shows.
  final List<BoardNotification> _popdownQueue = [];
  BoardNotification? _activePopdown;
  StreamSubscription<BoardNotification>? _popdownSub;



  /// All-clear detection — restores normal UI after emergency.
  StreamSubscription<BoardNotification>? _allClearSub;
  bool _showAllClearToast = false;
  Timer? _allClearToastTimer;

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
    );

    // Load timetable from Isar + subscribe to in-memory cache for live updates.
    // The cache is the single source of truth for the current slot — the local
    // _findCurrentSlot is removed in favour of TimetableCache().currentSlot.
    _loadInitialData(); // Isar read — local only, safe.
    _loadPreferences(); // SecureStorage read — local only, safe.
    _startNetworkMonitoring();

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

      // 1b. EARLY HYDRATION: Ensure board data is fetched from server
      //     before background protocols run. If HydrationProfile is missing
      //     from Isar (e.g. after restart/shutdown), hydrate immediately
      //     so the UI has real data (timetable, room number, etc.).
      try {
        final isar = Isar.getInstance();
        if (isar != null) {
          final profile = await isar.hydrationProfiles.where().findFirst();
          if (profile == null) {
            Log.i('[Idle] No HydrationProfile found — hydrating from server');
            await globalDeviceRepository.hydrateFromServer();
          } else {
            Log.i('[Idle] HydrationProfile exists (room=${profile.roomNumber})');
          }
        }
      } catch (e) {
        Log.w('[Idle] Early hydration check failed: $e');
      }

      if (!mounted) return;

      // 2. Start global background protocols (SyncManager, WindowOrchestrator,
      //    PreFlightService). These open Firestore listeners + a Timer that
      //    can call window_manager. Now safe because setMode has completed.
      //    Wrap in try/catch so post-protocol refresh ALWAYS runs, even if
      //    protocols partially fail (e.g. network timeout).
      try {
        await startBackgroundProtocols();
      } catch (e) {
        Log.e('[Idle] Background protocols failed: $e');
      }

      if (!mounted) return;

      // 3. The Firestore listener (or its REST fallback) already synced the
      //    timetable inside startBackgroundProtocols().  We only need to read
      //    from Isar to populate the UI state — no duplicate REST sync.
      await ApiService.syncTime().catchError((_) {
        Log.w('[Idle] Boot time sync failed — using cached skew.');
        return 0;
      });

      await _refreshTimetable();
      // Clear any stale completed sessions from previous days/weeks that
      // might have the same slot IDs as today's classes. Without this,
      // _completedSlotIds blocks the OTP card (via isBedrockCompleted)
      // even when the faculty has not yet taken attendance today.
      // FIX: Pass actual weekday so today's completed sessions are preserved
      // (critical for crash-recovery: the CompletedSession record prevents
      // OTP re-entry if the board restarts mid-session).
      await SessionManager.clearCompletedSessionsForDay(TimeSyncService.timeNow.weekday);
      // Load completed slots before starting the 10s timer so the first
      // _checkUpcomingClass() tick sees accurate data. Without this, a
      // release-build AOT race (debug JIT overhead hides it) leaves the
      // set empty, causing warm-up + OTP card to show for completed slots.
      await _loadCompletedSlots();
      await _checkActiveSession();
      _startPreClassTimer();
      _startCinematicMonitor();
      if (AppConfig.enableVideoBreaks) {
        _initVideoBackground();
      }

      // 4. Mark idle and drain any notifications that arrived during class.
      final notifService = NotificationListenerService();
      notifService.markIdle(true);
      final drained = notifService.drainQueue();
      if (drained.isNotEmpty) {
        for (final n in drained) {
          if (n.priority == NotificationPriority.emergency ||
              n.priority == NotificationPriority.high) {
            // Already handled by overlays — skip popdown
          } else if (n.priority == NotificationPriority.low) {
            setState(() {
              _popdownQueue.add(n);
              if (_activePopdown == null) {
                _showNextPopdown();
              }
            });
          }
        }
      }

      // 5. Listen for real-time incoming notifications.
      _popdownSub = notifService.onNotificationArrived.listen((n) {
        if (!mounted) return;
        // Route by priority:
        // - emergency/high → handled by overlays, skip popdown
        // - normal → handled by overlay (P-2), skip popdown
        // - low → show popdown animation (during breaks or as general info)
        if (n.priority == NotificationPriority.emergency ||
            n.priority == NotificationPriority.high) {
          // Overlays handle these — skip popdown
          Log.d('[Idle] Emergency/high notification — overlay handles display.');
        } else if (n.priority == NotificationPriority.low) {
          // Low priority (P-3) → show popdown animation
          setState(() {
            _popdownQueue.add(n);
            if (_activePopdown == null) {
              _showNextPopdown();
            }
          });
        }
      });

      // 6. Listen for all-clear events to restore normal UI.
      _allClearSub = notifService.onAllClear.listen((n) {
        if (!mounted) return;
        setState(() => _showAllClearToast = true);
        _allClearToastTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showAllClearToast = false);
        });
      });

      // 7. Listen for media push/clear events from WebSocket.
      try {
        _mediaPushSub = WebsocketService.onMediaPushStatic.listen((event) {
          if (!mounted) return;
          Log.i('[Idle] Media push received: ${event.sessionId} type=${event.mediaType}');
          setState(() => _activeMediaPush = event);
        });
        _mediaClearSub = WebsocketService.onMediaClearStatic.listen((sessionId) {
          if (!mounted) return;
          Log.i('[Idle] Media clear received: $sessionId');
          setState(() => _activeMediaPush = null);
        });
      } catch (e) {
        Log.w('[Idle] Failed to subscribe to media push events: $e');
      }

      // 8. If returning from a completed attendance session, keep the
      //    app on idle screen but show the minimize button so faculty
      //    can manually minimize if desired.
      if (widget.completedSession) {
        setState(() {
          _showMinimizeButton = true;
        });
      }
    });
  }

  void _showNextPopdown() {
    if (_popdownQueue.isEmpty) {
      setState(() => _activePopdown = null);
      return;
    }
    setState(() => _activePopdown = _popdownQueue.removeAt(0));
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

  void _startNetworkMonitoring() {
    final service = NetworkInfoService();
    service.startMonitoring(interval: const Duration(seconds: 10));
    _networkSub = service.onChanged.listen((info) {
      if (!mounted) return;

      // Debounce rapid network state changes to prevent UI flickering
      // Only update if state actually changed
      final wasOnline = _networkInfo.hasInternet;
      final isOnline = info.hasInternet;

      setState(() {
        _networkInfo = info;
        // Emergency minimize: show button when internet is lost
        if (!info.hasInternet) {
          _showMinimizeButton = true;
        }
      });

      // Log state transitions
      if (wasOnline != isOnline) {
        Log.i('[Idle] Network state changed: ${isOnline ? "ONLINE" : "OFFLINE"}');
      }
    });
    _networkInfo = service.current;
    // Initialize minimize button state based on current connectivity
    if (!service.current.hasInternet) {
      _showMinimizeButton = true;
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
    return _isCurrentBreak();
  }

  /// Check if we are currently in a break slot using explicit is_break flag.
  /// Falls back to time-gap detection if no explicit break entries exist.
  bool _isCurrentBreak() {
    return _getCurrentBreakEntry() != null;
  }

  /// Returns the current break entry if we are in a break slot, null otherwise.
  /// Uses explicit is_break flag from slot definitions.
  TimetableEntry? _getCurrentBreakEntry() {
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;

    // Check for explicit break entries
    for (final entry in _todayTimeline) {
      if (!entry.isBreak) continue;
      final startParts = entry.startTime.split(':');
      final endParts = entry.endTime.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      if (currentMinutes >= startMinutes && currentMinutes < endMinutes) {
        return entry;
      }
    }

    return null;
  }

  int _toMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  DateTime _computeSlotEndTime(String? slotId) {
    final now = TimeSyncService.timeNow;
    if (slotId != null && slotId.isNotEmpty) {
      for (final entry in _todayTimeline) {
        if (entry.slotId == slotId) {
          final parts = entry.endTime.split(':');
          if (parts.length == 2) {
            return DateTime(now.year, now.month, now.day,
                int.parse(parts[0]), int.parse(parts[1]));
          }
        }
      }
    }
    Log.w('[Idle] _computeSlotEndTime: slot $slotId not found in timetable — falling back to +1h');
    return now.add(const Duration(hours: 1));
  }

  bool _isPreBootPhase() {
    if (_bedrockEntry != null || _todayTimeline.isEmpty) return false;
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;
    // Find first class slot (skip breaks, tutorial, library)
    final classSlots = _todayTimeline.where((e) => !e.isBreak && e.slotType == 'regular').toList();
    if (classSlots.isEmpty) return false;
    final firstEntry = classSlots.first;
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
    // Find last class slot (skip breaks, tutorial, library)
    final classSlots = _todayTimeline.where((e) => !e.isBreak && e.slotType == 'regular').toList();
    if (classSlots.isEmpty) return false;
    for (final entry in classSlots) {
      final parts = entry.startTime.split(':');
      if (parts.length != 2) continue;
      int startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (startMinutes > currentMinutes) return false;
    }
    final lastEntry = classSlots.last;
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
    var initialTimeline = await deviceRepository.getTodayTimeline();
    if (initialTimeline.isEmpty) {
      initialTimeline = TimetableCache().todayTimeline;
    }
    if (mounted) {
      setState(() {
        _todayTimeline = initialTimeline;
        _bedrockEntry = TimetableCache().currentSlot;
      });
    }

    // Re-validate: if a session was recovered before timetable loaded, check
    // that its slotId matches the now-known current slot. If stale, discard.
    if (_activeSession != null && _activeSession!.slotId.isNotEmpty && _bedrockEntry != null) {
      if (_activeSession!.slotId != _bedrockEntry!.slotId) {
        Log.w('[Idle] Stale session ${_activeSession!.sessionId} (slot ${_activeSession!.slotId}) != current ${_bedrockEntry!.slotId} — clearing');
        await SessionManager.clearSession(_activeSession!.sessionId);
        if (mounted) {
          setState(() {
            _activeSession = null;
            _sessionStartTimestamp = null;
            _sessionScheduledEnd = null;
            _stopSessionProgressTimer();
            // TEMPORARY: button always visible — do not hide on stale session
          });
        }
      }
    }

    await _loadRoomNumber();
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
    _breakTimer?.cancel();
    _preFlightSessionSubscription?.cancel();
    _popdownSub?.cancel();
    _allClearSub?.cancel();
    _allClearToastTimer?.cancel();
    _networkSub?.cancel();
    _mediaPushSub?.cancel();
    _mediaClearSub?.cancel();
    NetworkInfoService().stopMonitoring();
    // Notifications arriving while on non-idle screens will be queued.
    NotificationListenerService().markIdle(false);
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
    var entries = await deviceRepository.getTodayTimeline();
    if (entries.isEmpty) {
      entries = TimetableCache().todayTimeline;
    }
    if (mounted) {
      setState(() {
        _todayTimeline = entries;
        _bedrockEntry = TimetableCache().currentSlot;
      });
    }
    await _loadRoomNumber();
  }

  /// Helper to extract session secret from server response.
  /// Server returns full session_secret directly (no split derivation needed).
  Future<String?> _deriveSecret(Map<String, dynamic> data) async {
    try {
      return data['session_secret']?.toString();
    } catch (e) {
      Log.e('[Idle] Secret extraction failed: $e');
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
      _stopBreakTimer();
      _t0RestoredSlots.clear();
      _cooldownFiredSlots.clear();
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

  Future<void> _checkActiveSession() async {
    // If we already have an active session, verify it's still lifecycle='active'
    // in Isar (i.e. hasn't been marked completed by SummaryScreen).
    if (_activeSession != null) {
      final exists = await SessionManager.sessionExists(_activeSession!.sessionId);
      if (!exists && mounted) {
        Log.i('[Idle] Active session ${_activeSession!.sessionId} no longer active — clearing.');
        setState(() {
          _activeSession = null;
          _sessionStartTimestamp = null;
          _sessionScheduledEnd = null;
          _stopSessionProgressTimer();
          // TEMPORARY: button always visible — do not hide when session cleared
        });
      }
      return;
    }

    // No active session yet — discover one. Only finds sessions with
    // lifecycle='active'. Completed or orphaned sessions are ignored.
    final session = await SessionManager.getResumeableSession(
      currentSlotId: _bedrockEntry?.slotId,
    );

    if (session != null && mounted) {
      setState(() {
        _activeSession = session;
        _showMinimizeButton = true;
        // For resumed sessions, use scheduledEndTime and estimate start
        _sessionScheduledEnd = session.scheduledEndTime;
        // Estimate start as (scheduledEnd - slot duration) if we can find it
        _sessionStartTimestamp = _computeSessionStartTime(session.slotId);
      });
      _startSessionProgressTimer();
    }
  }

  Future<void> _checkUpcomingClass() async {
    _checkActiveSession();
    if (_todayTimeline.isEmpty) return;

    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;

    // ── Next upcoming class ───────────────────────────────────────────────────
    // Computed early so class-end cooldown, T-5 cooldown, and T-3 warm-up
    // can all reference minDiff. Only consider class/lab slots — never break
    // or tutorial/library slots.
    TimetableEntry? nextEntry;
    int minDiff = 9999;

    for (final entry in _todayTimeline) {
      if (entry.isBreak) continue;
      if (entry.slotType != 'regular') continue;
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

      // Step 3: Clear any ActiveSession from a previous slot so crash
      // recovery does not resurrect a stale session for a different period.
      SessionManager.clearSessionsNotMatching(bedrockSlotId);

      // Step 4: If no session was transferred, enter PENDING state so the
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

      // Skip cooldown entirely when the next class starts within 2 minutes.
      // This prevents the 2-minute hard freeze from blocking the incoming
      // class's T-3 warm-up window (back-to-back classes scenario).
      if (minDiff <= 2) {
        Log.i('[Idle] Class ended but next class in $minDiff min — skipping cooldown.');
        // Essential cleanup only: wipe completed sessions, reset tracking.
        await SessionManager.clearCompletedSessionsForDay(TimeSyncService.timeNow.weekday);
        WindowOrchestratorService().resetAttendanceTracking();
        _evaluateNextClass();
        if (mounted) setState(() {});
        return;
      }

      // Start 2-minute hard cooldown only if attendance was NOT taken and
      // the cooldown hasn't already fired for this slot (prevents T-5 + class-end
      // double-fire and guards against 10s-timer re-entry after the first cycle).
      // FIX: Also skip cooldown if an active session exists — the session is
      // still in progress and wiping data would destroy crash-recovery state.
      if (!widget.completedSession &&
          _cooldownState == CooldownState.none &&
          !_cooldownFiredSlots.contains(endedSlotId) &&
          _activeSession == null) {
        if (!WindowOrchestratorService().hasTakenAttendance(endedSlotId)) {
          _cooldownFiredSlots.add(endedSlotId);
          _startCooldown();
        }
      }
    }
    if (bedrockSlotId == null) {
      _lastBedrockSlotId = null;
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
    // Also skip when minDiff <= 2 — the next class is imminent; starting a
    // cooldown would block the warm-up and create a loop.
    // FIX: Also skip when _activeSession is non-null — the session is still
    // in progress and starting cooldown would destroy crash-recovery state.
    Log.iThrottled('t5_check',
        '[Idle T-5] bedrock=$_bedrockEntry cooldown=$_cooldownState preAlloc=$_preAllocatedSessionId upAlloc=$_upcomingAllocatedSessionId minDiff=$minDiff endTime=${_bedrockEntry?.endTime} now=$currentMinutes');
    if (_bedrockEntry != null &&
        _cooldownState != CooldownState.locked &&
        _preAllocatedSessionId == null &&
        _upcomingAllocatedSessionId == null &&
        _activeSession == null &&
        minDiff > 2) {
      final endParts = _bedrockEntry!.endTime.split(':');
      if (endParts.length == 2) {
        final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
        final diffToEnd = endMinutes - currentMinutes;
        if (diffToEnd <= 5 && diffToEnd > 0) {
          final slotId = _bedrockEntry!.slotId;
          if (!_cooldownFiredSlots.contains(slotId) &&
              !WindowOrchestratorService().hasTakenAttendance(slotId)) {
            _cooldownFiredSlots.add(slotId);
            Log.w('[Idle] T-5 proactive cooldown for slot $slotId — attendance not taken.');
            _startCooldown();
            return;
          } else {
            Log.i('[Idle T-5] Blocked: alreadyFired=${_cooldownFiredSlots.contains(slotId)} attendanceTaken=${WindowOrchestratorService().hasTakenAttendance(slotId)}');
          }
        } else {
          Log.i('[Idle T-5] Not in window: diffToEnd=$diffToEnd');
        }
      }
    }

    // ── Cooldown guard ─────────────────────────────────────────────────────
    // During the 2-minute hard freeze, all T-3/T-0 processing is skipped.
    // After cooldown completes, _evaluateNextClass handles the next-link chain.
    // Break timer continues running in background during cooldown.
    if (_cooldownState == CooldownState.locked) {
      return;
    }

    // ── Current Class State ───────────────────────────────────────────────────
    // Manages the OTP card visibility and session transfer for the active class.
    // Warm-up at T-3 is handled exclusively by the upcoming-class block below.
    if (_bedrockEntry != null) {
      _stopBreakTimer();
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
        final classSlots = _todayTimeline.where((e) => !e.isBreak && e.slotType == 'regular').toList();
        final bool isFirstClass = classSlots.isNotEmpty &&
            classSlots.first.slotId == nextEntry.slotId;
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

      // ── Break Timer Management ─────────────────────────────────────────────
      // Start the break countdown when we are in an explicit break slot from
      // the timetable. Only uses slot_definitions data — no gap detection.
      if (_bedrockEntry == null &&
          _cooldownState == CooldownState.none &&
          !_showStartingSoon) {
        final now = TimeSyncService.timeNow;
        final currentSeconds = now.hour * 3600 + now.minute * 60 + now.second;

        // Check for explicit break entries from timetable
        bool inBreak = false;
        for (final entry in _todayTimeline) {
          if (!entry.isBreak) continue;
          final startParts = entry.startTime.split(':');
          final endParts = entry.endTime.split(':');
          if (startParts.length < 2 || endParts.length < 2) continue;
          final startSeconds = int.parse(startParts[0]) * 3600 + int.parse(startParts[1]) * 60;
          final endSeconds = int.parse(endParts[0]) * 3600 + int.parse(endParts[1]) * 60;
          if (currentSeconds >= startSeconds && currentSeconds < endSeconds) {
            inBreak = true;
            final totalSeconds = endSeconds - startSeconds;
            final remainingSeconds = endSeconds - currentSeconds;
            if (remainingSeconds > 0 && _breakTimer == null) {
              _startBreakTimer(totalSeconds, remainingSeconds);
            }
            break;
          }
        }

        // If not in a break and timer exists, stop it
        if (!inBreak && _breakTimer != null) {
          _stopBreakTimer();
        }
      }
    }
  }

  // ── 2-Minute Hard Cooldown ────────────────────────────────────────────────

  /// Enters the locked cooldown state and starts a 120-second countdown.
  /// Clears all previous-class state immediately so the cooldown phase shows
  /// a clean slate. The next-class T-3 re-evaluation happens on completion.
  Future<void> _startCooldown() async {
    _fullCleanup();
    // FIX: Only wipe active sessions if there is NO resumable session in Isar.
    // If _activeSession is non-null, the faculty has an active attendance
    // session that must survive the cooldown (e.g. app restart mid-session).
    // Clearing it here would destroy the recovery data and force OTP re-entry.
    if (_activeSession == null) {
      await SessionManager.clearAllActiveSessions();
    } else {
      Log.i('[Idle] Cooldown skipped clearing active sessions — session ${_activeSession!.sessionId} is resumable.');
    }
    await SessionManager.clearCompletedSessionsForDay(TimeSyncService.timeNow.weekday);
    WindowOrchestratorService().resetAttendanceTracking();
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
  /// Unlocks the cooldown state then evaluates the next class T-3 window.
  /// Full cache cleanse already happened at [_startCooldown].
  void _onCooldownComplete() {
    _cooldownState = CooldownState.none;
    _evaluateNextClass();
    // Start break timer immediately so there is no ~10s dead gap while waiting
    // for the next periodic _checkUpcomingClass tick.
    _kickstartBreakTimerIfNeeded();
    if (mounted) setState(() {});
    Log.i('[Idle] Cooldown complete. Cache cleansed, next-link evaluated.');
  }

  /// Starts the break timer right now when we are in an explicit break slot
  /// from the timetable. Called after cooldown completes to ensure the break
  /// timer is running even during T-3 window, providing continuous ring progress.
  /// Only uses explicit break entries from slot_definitions — no gap detection.
  void _kickstartBreakTimerIfNeeded() {
    if (_breakTimer != null || _todayTimeline.isEmpty) return;
    if (_bedrockEntry != null) return;

    final now = TimeSyncService.timeNow;
    final currentSeconds = now.hour * 3600 + now.minute * 60 + now.second;

    // Check for explicit break entries from timetable only
    for (final entry in _todayTimeline) {
      if (!entry.isBreak) continue;
      final startParts = entry.startTime.split(':');
      final endParts = entry.endTime.split(':');
      if (startParts.length < 2 || endParts.length < 2) continue;
      final startSeconds = int.parse(startParts[0]) * 3600 + int.parse(startParts[1]) * 60;
      final endSeconds = int.parse(endParts[0]) * 3600 + int.parse(endParts[1]) * 60;
      if (currentSeconds >= startSeconds && currentSeconds < endSeconds) {
        final totalSeconds = endSeconds - startSeconds;
        final remainingSeconds = endSeconds - currentSeconds;
        if (remainingSeconds > 0) {
          _startBreakTimer(totalSeconds, remainingSeconds);
          return;
        }
      }
    }
    // No fallback — if no explicit break exists, don't start timer
  }

  /// Full cache cleanse — wipes all warm-up state, session IDs, and tracking
  /// registers so the next class starts with a clean slate.
  /// Does NOT reset cooldown state or break timer — those are managed
  /// independently by their own lifecycle methods.
  void _fullCleanup() {
    _warmUpTriggeredSlotId = null;
    _completedWarmUpSlots.clear();
    _preFlightStatus = PreFlightStatus.none;
    _preFlightError = null;
    _forceShowCard = false;
    _showStartingSoon = false;
    // TEMPORARY: button always visible — do not reset on slot transition
    _showSessionMenu = false;
    _isKeypadExpanded = false;
    _upcomingSlot = null;
    _preAllocatedSessionId = null;
    _upcomingAllocatedSessionId = null;
    // Note: _cooldownState and _breakTimer are NOT reset here.
    // They have their own lifecycle methods (_startCooldown, _stopBreakTimer).
    _otpController.clear();
  }

  // ── Break Countdown Timer ──────────────────────────────────────────────────

  /// Starts the break countdown timer that runs from break start through T-3
  /// until the next class begins. The progress ring continues seamlessly into
  /// the T-3 green state without resetting.
  void _startBreakTimer(int totalSeconds, int remainingSeconds) {
    _breakTimer?.cancel();
    _breakDurationSeconds = totalSeconds;
    _breakSecondsRemaining = remainingSeconds;
    _breakTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _breakSecondsRemaining--;
        if (_breakSecondsRemaining <= 0) {
          _breakTimer?.cancel();
          _breakTimer = null;
          _breakSecondsRemaining = 0;
        }
      });
    });
    if (mounted) setState(() {});
    Log.i('[Idle] Break timer started: ${totalSeconds}s total, ${remainingSeconds}s remaining.');
  }

  /// Stops and resets the break countdown timer.
  void _stopBreakTimer() {
    _breakTimer?.cancel();
    _breakTimer = null;
    _breakSecondsRemaining = 0;
    _breakDurationSeconds = 0;
  }

  // ── Session Progress Timer ────────────────────────────────────────────────

  /// Starts a 1-second periodic timer that triggers setState to update the
  /// session progress ring. The ring shows how much time has elapsed since
  /// the session started relative to the scheduled slot duration.
  void _startSessionProgressTimer() {
    _sessionProgressTimer?.cancel();
    _sessionProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Just trigger setState — the ring value is computed in build
      setState(() {});
    });
  }

  /// Stops the session progress timer.
  void _stopSessionProgressTimer() {
    _sessionProgressTimer?.cancel();
    _sessionProgressTimer = null;
  }

  /// Computes the session start time from the timetable slot start time.
  /// Returns the slot's start time as a DateTime for today.
  DateTime _computeSessionStartTime(String slotId) {
    final now = TimeSyncService.timeNow;
    if (slotId.isNotEmpty) {
      for (final entry in _todayTimeline) {
        if (entry.slotId == slotId) {
          final parts = entry.startTime.split(':');
          if (parts.length == 2) {
            return DateTime(now.year, now.month, now.day,
                int.parse(parts[0]), int.parse(parts[1]));
          }
        }
      }
    }
    // Fallback: assume session started 1 hour ago
    return now.subtract(const Duration(hours: 1));
  }

  /// Computes the session progress as a value between 0.0 and 1.0.
  /// Uses actual start time and scheduled end time from the slot.
  /// Handles late starts correctly — if faculty starts 10 min before end,
  /// the ring fills from 0% to 100% in those 10 minutes.
  double _computeSessionProgress() {
    if (_activeSession == null || _sessionStartTimestamp == null) return 0.0;

    final now = TimeSyncService.timeNow;
    final scheduledEnd = _sessionScheduledEnd ?? _activeSession!.scheduledEndTime;
    final start = _sessionStartTimestamp!;

    // Total duration = scheduledEnd - actualStart (handles late starts)
    final totalDuration = scheduledEnd.difference(start).inSeconds;
    // Elapsed = now - actualStart
    final elapsed = now.difference(start).inSeconds;

    if (totalDuration <= 0) return 1.0;
    return (elapsed / totalDuration).clamp(0.0, 1.0);
  }

  /// Returns the session progress ring color based on how much time is left.
  Color _getSessionProgressColor() {
    final progress = _computeSessionProgress();
    if (progress >= 1.0) return AppColors.successLime; // Session complete
    if (progress >= 0.8) return AppColors.warningAmber; // Almost done
    return AppColors.primaryTeal; // In progress
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
      if (entry.isBreak) continue;
      if (entry.slotType != 'regular') continue;
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
      final classSlots = _todayTimeline.where((e) => !e.isBreak && e.slotType == 'regular').toList();
      final bool isFirstClass = classSlots.isNotEmpty &&
          classSlots.first.slotId == nextEntry.slotId;
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
    // Guard: don't trigger another warm-up if a session is already allocated
    // for any slot. This prevents race conditions where multiple timer ticks
    // allocate duplicate sessions for the same or different slots.
    if (!force && (_preAllocatedSessionId != null || _upcomingAllocatedSessionId != null)) {
      Log.i('[Idle] Warm-up skipped for $slotId — session already allocated (preAlloc=$_preAllocatedSessionId upAlloc=$_upcomingAllocatedSessionId)');
      return;
    }

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
    if (otp.length != 4) {
      setState(() => _errorMessage = 'Please enter a valid 4-digit PIN');
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
          data['section_id']?.toString() ?? data['context_ids']?['section_id']?.toString() ?? widget.registration.smartBoardId;
      if (sessionId == null || sessionSecret == null) {
        setState(() => _errorMessage =
            'Invalid server response: missing session data. Please try again with a new PIN.');
        return;
      }

      final slotId = _upcomingSlot?.slotId ?? _bedrockEntry?.slotId;

      final scheduledEndTime = _computeSlotEndTime(slotId);

      await SessionManager.saveSession(
        sessionId: sessionId,
        rosterCount: rosterCount,
        facultyName: facultyName,
        courseName: courseName,
        sectionId: sectionId,
        endTime: scheduledEndTime,
        slotId: slotId ?? '',
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
        if (mounted) {
          setState(() => _completedSlotIds.add(slotId));
        }
      }

      MetricsCollector().recordSessionStart();
      await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);

      // Session is now live — clear the in-memory pre-allocated IDs so they
      // cannot be accidentally reused if the board returns to IdleScreen.
      if (mounted) {
        setState(() {
          _preAllocatedSessionId = null;
          _upcomingAllocatedSessionId = null;
          _showMinimizeButton = true;
          _forceShowCard = false;
          _isKeypadExpanded = false;
          _showSessionMenu = false;
        });
      }

      if (mounted) {
        final now = TimeSyncService.timeNow;
        final activeSession = ActiveSession()
          ..sessionId = sessionId
          ..slotId = slotId ?? ''
          ..courseName = courseName
          ..facultyName = facultyName
          ..sectionId = sectionId
          ..rosterCount = rosterCount
          ..scheduledEndTime = scheduledEndTime
          ..presentIndices = []
          ..absentIndices = []
          ..verifiedStudentIds = [];
        setState(() {
          _activeSession = activeSession;
          _sessionStartTimestamp = now;
          _sessionScheduledEnd = scheduledEndTime;
        });
        _startSessionProgressTimer();
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
          // FIX: Also suppress the OTP card when a resumable session exists in
          // Isar. Without this guard, a crash+restart during an active session
          // causes the OTP card to reappear because clearCompletedSessionsForDay()
          // wipes the completed-slot marker on boot.
          final bool hasActiveSession = _activeSession != null;
          final bool showCardContextually = (_forceShowCard || _bedrockEntry != null) &&
              _cooldownState != CooldownState.locked &&
              (_forceShowCard || (!isBedrockCompleted && !hasActiveSession));

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
          final double horizontalPad =
              (size.width * 0.05).clamp(20.0, 80.0);
          final bool isNarrow = size.width < 1200;
          final double cardMaxWidth =
              isNarrow ? 280.0 : (size.width * 0.2).clamp(240.0, 340.0);

          Widget mainContent;
          if (isNarrow) {
            mainContent = SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildCourseInfo(
                      primaryTextColor, secondaryTextColor, showVideo),
                  const SizedBox(height: 30),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardMaxWidth),
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
                          showVideo && !isBlindlyWhite,
                          cardMaxWidth),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          } else {
            mainContent = Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
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
                              constraints:
                                  BoxConstraints(maxWidth: cardMaxWidth),
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
                                  showVideo && !isBlindlyWhite,
                                  cardMaxWidth),
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
            );
          }

          stackChildren.add(Column(
            children: [
              _buildTopHeader(primaryTextColor, headerFooterColor, showVideo),
              Expanded(child: mainContent),
              _buildFooter(
                  headerFooterColor, primaryTextColor, secondaryTextColor,
                  showVideo),
            ],
          ));

          // 5. Active Session Overlay
          if (_showSessionMenu && _activeSession != null) {
            stackChildren.add(_buildActiveSessionOverlay(primaryTextColor, secondaryTextColor));
          }

          // 5b. Notification popdown (top-sliding banner)
          if (_activePopdown != null) {
            stackChildren.add(
              Positioned(
                top: 82,
                right: 40,
                child: NotificationPopdown(
                  key: ValueKey(_activePopdown!.id),
                  notification: _activePopdown!,
                  onDismiss: _showNextPopdown,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  )),
                ),
              ),
            );
          }

          // 7. All-clear toast
          if (_showAllClearToast) {
            stackChildren.add(
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'All Clear — Emergency resolved',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          // 8. WiFi status in footer — handled by _buildClockAndInfo

          // 9. Media overlay (highest priority — above everything)
          if (_activeMediaPush != null) {
            stackChildren.add(MediaOverlay(
              event: _activeMediaPush!,
              onClear: () {
                if (mounted) {
                  setState(() => _activeMediaPush = null);
                }
              },
            ));
          }

          return Stack(children: stackChildren);
        },
      ),
    );
  }

  Widget _buildTopHeader(Color textColor, Color bgColor, bool isVideoActive) {
    final size = MediaQuery.of(context).size;
    final double hPad = (size.width * 0.03).clamp(16.0, 40.0);
    final double vPad = (size.height * 0.02).clamp(12.0, 20.0);
    final double logoSize = (size.width * 0.025).clamp(28.0, 36.0);
    final double titleFontSize = (size.width * 0.017).clamp(18.0, 24.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.8),
        border:
            Border(bottom: BorderSide(color: textColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo_square.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Text(
                'IntelliAttend SmartBoard',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w900,
                  color: textColor == Colors.white
                      ? Colors.white
                      : AppColors.primaryTeal,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNavLinks(textColor),
              const SizedBox(width: 40),
              _buildHeaderActions(textColor),
            ],
          ),
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
        NotificationBell(
          iconColor: iconColor,
          onViewAll: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => const NotificationsScreen())),
        ),
        // ──────────────────────────────────────────────────────────────────
        if (_showMinimizeButton)
          IconButton(
            onPressed: () => KioskService.setMode(KioskMode.suspended),
            icon: Icon(Icons.minimize_rounded, color: iconColor),
            tooltip: 'Minimize to Desktop',
          ),
        IconButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const SettingsScreen()));
              _loadPreferences();
            },
            icon: Icon(Icons.settings_outlined, color: iconColor)),
      ],
    );
  }

  String _getRoomName() {
    final room = (_roomNumber != null && _roomNumber!.isNotEmpty)
        ? _roomNumber!
        : widget.registration.roomName;
    if (room.isEmpty) return 'Unknown';
    if (room.toLowerCase().startsWith('hall')) {
      return room;
    }
    return 'Hall $room';
  }

  Future<void> _loadRoomNumber() async {
    try {
      final isar = Isar.getInstance();
      if (isar != null) {
        final profile = await isar.hydrationProfiles.where().findFirst();
        if (mounted) {
          setState(() {
            _roomNumber = profile?.roomNumber;
          });
        }
      }
    } catch (e) {
      Log.e('[IdleScreen] Failed to load hydration profile room: $e');
    }
  }

  /// Normalises the raw class_type value from the server into a human-readable
  /// label. The server may send 'regular', 'lecture', 'lab', 'laboratory', or
  /// null/empty. Returns 'Lecture', 'Lab', or 'Unknown' accordingly.
  String _normalizeClassType(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'lecture':
      case 'regular':
        return 'Lecture';
      case 'lab':
      case 'laboratory':
        return 'Lab';
      case null:
      case '':
        return 'Unknown';
      default:
        // Title-case any other non-empty value the server may send in future
        final t = raw!.trim();
        return t[0].toUpperCase() + t.substring(1).toLowerCase();
    }
  }



  Widget _buildCourseInfo(
      Color primaryColor, Color secondaryColor, bool isVideoActive) {
    final isSunday = TimeSyncService.timeNow.weekday == DateTime.sunday;
    final currentBreak = _getCurrentBreakEntry();
    final hasBreak = currentBreak != null;

    var course = _bedrockEntry?.courseName ?? '';
    var faculty = _bedrockEntry?.facultyName ?? '';

    if (isSunday && _bedrockEntry == null) {
      course = 'SUNDAY FUNDAY';
      faculty = 'SYSTEM IDLE';
    } else if (hasBreak) {
      // Show explicit break name from slot definitions
      course = currentBreak.periodName?.toUpperCase() ?? 'BREAK TIME';
      faculty = 'REFRESH';
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
                  const SizedBox(height: 2),
                  Text(
                    '${_getRoomName()} • ${_normalizeClassType(_bedrockEntry?.classType)}',
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
                child: const Icon(
                    Icons.coffee_outlined,
                    color: AppColors.primaryTeal),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentBreak.periodName?.toUpperCase() ?? 'BREAK TIME',
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
            fontSize: (MediaQuery.of(context).size.width * 0.04).clamp(36.0, 64.0),
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
      bool isVideoActive, double cardWidth) {
    final double cardPadding = cardWidth < 260 ? 12.0 : 16.0;
    final double titleFontSize = (cardWidth * 0.045).clamp(11.0, 14.0);
    final double bodyFontSize = (cardWidth * 0.035).clamp(9.0, 11.0);
    final double statusFontSize = (cardWidth * 0.03).clamp(8.0, 10.0);
    final double buttonHeight = cardWidth < 260 ? 34.0 : 40.0;
    final double buttonFontSize = (cardWidth * 0.04).clamp(10.0, 13.0);
    final double iconSize = (cardWidth * 0.05).clamp(12.0, 18.0);
    final double lockIconSize = (cardWidth * 0.055).clamp(12.0, 18.0);
    final double pinAvailableWidth = (cardWidth - cardPadding * 2 - 16).clamp(100.0, 260.0);
    final double verticalGap = cardWidth < 260 ? 16.0 : 24.0;

    return GlassContainer(
      padding: EdgeInsets.all(cardPadding),
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'START ATTENDANCE',
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
              Icon(Icons.lock_open_outlined,
                  size: lockIconSize, color: secondaryColor.withValues(alpha: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the session code displayed on your mobile device to begin Session.',
            style: TextStyle(
              fontSize: bodyFontSize,
              color: secondaryColor,
            ),
          ),
          SizedBox(height: verticalGap),
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
                availableWidth: pinAvailableWidth,
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _buildNumericKeypad(
                  primaryColor == Colors.white, isVideoActive, cardWidth),
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
                  style: TextStyle(color: AppColors.error, fontSize: bodyFontSize),
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
                    fontSize: statusFontSize,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          SizedBox(height: verticalGap),
          SizedBox(
            width: double.infinity,
            height: buttonHeight,
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
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: iconSize),
                        SizedBox(width: cardWidth < 280 ? 6 : 10),
                        Text('SUBMIT',
                            style: TextStyle(
                                fontSize: buttonFontSize,
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
                    style: TextStyle(
                      fontSize: statusFontSize,
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
                    child: Text(
                      'ENCRYPTED SESSION',
                      style: TextStyle(
                        fontSize: statusFontSize,
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

  Widget _buildFooter(Color bgColor, Color primaryColor, Color secondaryColor,
      bool isVideoActive) {
    final size = MediaQuery.of(context).size;
    final double footerHeight = (size.height * 0.1).clamp(70.0, 100.0);
    final double hPad = (size.width * 0.03).clamp(16.0, 40.0);

    // Filter to only class/lab slots (no breaks, tutorial, library)
    final classSlots = _todayTimeline.where((e) => !e.isBreak && e.slotType == 'regular').toList();

    return Container(
      height: footerHeight,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isVideoActive ? 0.5 : 0.9),
        border:
            Border(top: BorderSide(color: primaryColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          // Timeline
          Expanded(
            child: classSlots.isEmpty
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
                      for (int i = 0; i < classSlots.length; i++) ...[
                        if (i > 0)
                          _buildTimelineSeparator(classSlots[i - 1], classSlots[i]),
                        Expanded(
                          child: _buildTimelineSlotFromClass(classSlots[i]),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(width: 20),
          // WiFi status icon — color indicates state
          _buildWifiStatusIcon(),
          const SizedBox(width: 20),
          // Clock — right-aligned
          _buildClockAndInfo(primaryColor, secondaryColor),
        ],
      ),
    );
  }

  /// Build a separator between two class slots.
  /// If there's a break between them, show a green line.
  Widget _buildTimelineSeparator(TimetableEntry prev, TimetableEntry next) {
    // Check if there's a break between these two slots
    final hasBreakBetween = _todayTimeline.any((e) =>
        e.isBreak &&
        _toMinutes(e.startTime) >= _toMinutes(prev.endTime) &&
        _toMinutes(e.endTime) <= _toMinutes(next.startTime));

    return Container(
      width: hasBreakBetween ? 2 : 1,
      height: 30,
      color: hasBreakBetween
          ? AppColors.primaryTeal.withValues(alpha: 0.6)
          : AppColors.textSecondaryDark.withValues(alpha: 0.1),
    );
  }

  /// Build timeline slot for a class entry (skip breaks).
  Widget _buildTimelineSlotFromClass(TimetableEntry entry) {
    final live = entry.slotId == _bedrockEntry?.slotId;
    final isCompleted = _completedSlotIds.contains(entry.slotId);
    final isFailed = _failedSlotIds.contains(entry.slotId);
    return TimelineSlot(
      entry: entry,
      isLive: live,
      isCompleted: isCompleted,
      isFailed: isFailed,
    );
  }

  Widget _buildWifiStatusIcon() {
    final info = _networkInfo;
    final netColor = !info.isConnected
        ? AppColors.error
        : !info.hasInternet
            ? const Color(0xFFF59E0B)
            : AppColors.primaryTeal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 70,
          child: Icon(
            !info.isConnected
                ? Icons.wifi_off_rounded
                : info.connectionType == 'Ethernet'
                    ? Icons.lan_rounded
                    : Icons.wifi_rounded,
            size: 22,
            color: netColor,
          ),
        ),
        if (info.isConnected) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: 70,
            child: Center(
              child: NumberFlow(
                value: info.realTimeMbps,
                decimalPlaces: info.realTimeMbps >= 10 ? 0 : 1,
                suffix: ' Mbps',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: netColor.withValues(alpha: 0.8),
                ),
                spinDuration: const Duration(milliseconds: 500),
                spinCurve: Curves.easeOut,
                transformDuration: const Duration(milliseconds: 350),
                transformCurve: Curves.easeOut,
                opacityDuration: const Duration(milliseconds: 250),
                opacityCurve: Curves.easeOut,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildClockAndInfo(Color primaryColor, Color secondaryColor) {
    final size = MediaQuery.of(context).size;
    final double clockFontSize = (size.width * 0.017).clamp(18.0, 24.0);
    final double dateFontSize = (size.width * 0.007).clamp(8.0, 10.0);

    return StreamBuilder<DateTime>(
      stream: Stream.periodic(
          const Duration(seconds: 1), (_) => TimeSyncService.timeNow),
      builder: (context, snapshot) {
        final now = snapshot.data ?? TimeSyncService.timeNow;
        final timeStr =
            "${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')}";
        final period = now.hour >= 12 ? 'PM' : 'AM';

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "$timeStr $period",
              style: GoogleFonts.jetBrainsMono(
                fontSize: clockFontSize,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            Text(
              _getFormattedDate(now).toUpperCase(),
              style: TextStyle(
                fontSize: dateFontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: secondaryColor.withValues(alpha: 0.5),
              ),
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

  Widget _buildActiveSessionOverlay(Color primaryText, Color secondaryText) {
    final session = _activeSession!;
    final size = MediaQuery.of(context).size;
    final double overlayWidth = (size.width * 0.35).clamp(280.0, 480.0);
    final double overlayPadding = (size.width * 0.02).clamp(12.0, 24.0);
    final double titleFontSize = (size.width * 0.012).clamp(12.0, 16.0);
    final double subtitleFontSize = (size.width * 0.008).clamp(10.0, 12.0);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Container(
            width: overlayWidth,
            padding: EdgeInsets.all(overlayPadding),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x1A000000)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0x2214B8A6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x3314B8A6)),
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF14B8A6), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Session Active',
                            style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 4),
                          Text('${session.courseName} · ${session.facultyName}',
                            style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: const Color(0xFF94A3B8)),
                      onPressed: () => setState(() => _showSessionMenu = false),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Divider(height: 1, color: const Color(0x1A000000)),
                const SizedBox(height: 24),
                // 2x2 grid layout for action cards
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.dashboard_rounded,
                            label: 'Workspace',
                            subtitle: 'Files & session tools',
                            color: const Color(0xFF14B8A6),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => WorkspaceScreen(
                                sessionId: session.sessionId,
                                courseName: session.courseName,
                                facultyName: session.facultyName,
                                roomName: widget.registration.roomName,
                                sectionId: session.sectionId,
                                slotId: null,
                                presentCount: session.presentIndices.length,
                                totalCapacity: session.rosterCount,
                              )),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.people_rounded,
                            label: 'Attendance',
                            subtitle: 'Mark present/absent',
                            color: const Color(0xFF8B5CF6),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => AttendanceScreen(
                                  sessionId: session.sessionId,
                                  capacity: session.rosterCount,
                                  courseName: session.courseName,
                                  facultyName: session.facultyName,
                                  roomName: widget.registration.roomName,
                                  slotId: null,
                                  initialPresentCount: session.presentIndices.length,
                                  boardId: widget.registration.smartBoardId,
                                  onNavigateBack: () => Navigator.of(context).pop(),
                                )),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.analytics_outlined,
                            label: 'Analytics',
                            subtitle: 'Session statistics',
                            color: const Color(0xFFF59E0B),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.calendar_month_rounded,
                            label: 'Timetable',
                            subtitle: 'View schedule',
                            color: const Color(0xFF3B82F6),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TimetableScreen(
                                weeklyTimeline: TimetableCache().weeklyTimeline,
                              )),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x1A000000)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                style: TextStyle(fontSize: 11, color: const Color(0xFF94A3B8)),
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
    // FIX: Treat an active session in Isar as "completed" for the hanging lock
    // so the lock shows "SESSION IN PROGRESS" / "VIEW SESSION" even if the
    // CompletedSession record was wiped on boot.
    final hasActiveSessionForSlot = _activeSession != null;
    final isUnlocked =
        _showStartingSoon && !isSlotCompleted && _upcomingAllocatedSessionId != null;
    final isWarmingUp =
        _showStartingSoon && !isSlotCompleted && !isUnlocked;
    final isWiping = _cooldownState == CooldownState.locked;

    // Break timer is active during break time regardless of cooldown/T-3 state
    final isBreakTimerActive = _breakTimer != null &&
        _breakSecondsRemaining > 0 &&
        !isSlotCompleted &&
        !hasActiveSessionForSlot;

    // Get current break entry for label
    final currentBreak = _getCurrentBreakEntry();

    // ── Ring progress & colour ──────────────────────────────────────────────
    // Priority: Active Session > Slot Completed > Cooldown+Break > T-3+Break > Break only
    double ringValue = 0.0;
    Color ringColor = Colors.transparent;
    bool showRing = false;

    if (hasActiveSessionForSlot) {
      // Session active: show progress based on actual elapsed time
      ringValue = _computeSessionProgress();
      ringColor = _getSessionProgressColor();
      showRing = true;
    } else if (isSlotCompleted) {
      ringValue = 1.0;
      ringColor = AppColors.warningAmber;
      showRing = true;
    } else if (isBreakTimerActive) {
      // Break is the base layer — always use break progress
      ringValue = _breakSecondsRemaining / _breakDurationSeconds;
      showRing = true;

      // Overlay: cooldown changes color to red
      if (isWiping) {
        ringColor = AppColors.error;
      }
      // Overlay: T-3 changes color to green
      else if (isUnlocked || isWarmingUp) {
        ringColor = AppColors.successLime;
      }
      // Default: teal for break
      else {
        ringColor = AppColors.primaryTeal;
      }
    } else if (isWiping) {
      // No break timer, but cooldown active
      ringValue = _cooldownSecondsRemaining / 120.0;
      ringColor = AppColors.error;
      showRing = true;
    } else if (isUnlocked || isWarmingUp) {
      // No break timer, but T-3 active
      ringValue = 1.0;
      ringColor = AppColors.successLime;
      showRing = true;
    }

    // ── Label ───────────────────────────────────────────────────────────────
    String label;
    if (hasActiveSessionForSlot) {
      label = 'SESSION IN PROGRESS';
    } else if (isSlotCompleted) {
      label = 'COMPLETED';
    } else if (isBreakTimerActive) {
      // Use explicit break name from slot definitions
      final breakName = currentBreak?.periodName?.toUpperCase() ?? 'BREAK';
      final minutes = (_breakSecondsRemaining / 60).floor();
      final seconds = _breakSecondsRemaining % 60;
      label = '$breakName\n${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (isWiping) {
      final minutes = (_cooldownSecondsRemaining / 60).floor();
      final seconds = _cooldownSecondsRemaining % 60;
      label = 'COOLDOWN\n${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (isUnlocked) {
      label = 'TAP TO START';
    } else if (isWarmingUp) {
      label = 'WARMING UP...';
    } else {
      label = 'SESSION LOCKED';
    }

    // ── Theme colours per state ─────────────────────────────────────────────
    Color themeColor;
    if (isSlotCompleted && _activeSession != null) {
      themeColor = AppColors.primaryTeal;
    } else if (hasActiveSessionForSlot) {
      themeColor = AppColors.primaryTeal;
    } else if (isSlotCompleted) {
      themeColor = AppColors.warningAmber;
    } else if (isUnlocked || isWarmingUp) {
      themeColor = AppColors.successLime;
    } else if (isWiping) {
      themeColor = AppColors.error;
    } else if (isBreakTimerActive) {
      themeColor = AppColors.primaryTeal;
    } else {
      themeColor = color.withValues(alpha: 0.5);
    }

    return InkWell(
      onTap: isUnlocked && !isWiping && !isWarmingUp
          ? () {
              setState(() {
                _forceShowCard = true;
                _isKeypadExpanded = true;
              });
              _resetInactivityTimer();
            }
          : (isSlotCompleted || hasActiveSessionForSlot) && _activeSession != null
              ? () => setState(() => _showSessionMenu = true)
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
              if (showRing)
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: ringValue,
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    backgroundColor: ringColor.withValues(alpha: 0.1),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isSlotCompleted || hasActiveSessionForSlot) && _activeSession != null
                      ? AppColors.primaryTeal.withValues(alpha: 0.15)
                      : isSlotCompleted
                          ? AppColors.warningAmber.withValues(alpha: 0.15)
                          : isUnlocked || isWarmingUp
                              ? AppColors.successLime.withValues(alpha: 0.15)
                              : isWiping
                                  ? AppColors.error.withValues(alpha: 0.15)
                                  : isBreakTimerActive
                                      ? AppColors.primaryTeal.withValues(alpha: 0.15)
                                      : color.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (isSlotCompleted || hasActiveSessionForSlot) && _activeSession != null
                        ? AppColors.primaryTeal.withValues(alpha: 0.3)
                        : isSlotCompleted
                            ? AppColors.warningAmber.withValues(alpha: 0.3)
                            : isUnlocked || isWarmingUp
                                ? AppColors.successLime.withValues(alpha: 0.3)
                                : isWiping || isBreakTimerActive
                                    ? Colors.transparent
                                    : color.withValues(alpha: 0.1),
                  ),
                ),
                child: Icon(
                  hasActiveSessionForSlot
                      ? Icons.arrow_forward_rounded
                      : isSlotCompleted
                          ? Icons.check_circle_outline_rounded
                          : isUnlocked
                              ? Icons.lock_open_outlined
                              : Icons.lock_outline,
                  color: themeColor,
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
              color: themeColor,
              fontSize: (MediaQuery.of(context).size.width * 0.007).clamp(8.0, 10.0),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad(
      bool isDark, bool isVideoActive, double cardWidth) {
    final double spacing = cardWidth < 260 ? 3.0 : 6.0;
    final double aspectRatio = cardWidth < 260 ? 1.4 : 1.7;
    final double buttonFontSize = (cardWidth * 0.045).clamp(12.0, 15.0);
    final double backspaceIconSize = (cardWidth * 0.045).clamp(11.0, 15.0);

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: aspectRatio,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++)
          _keypadButton(i.toString(), isDark, isVideoActive,
              fontSize: buttonFontSize, backspaceIconSize: backspaceIconSize),
        const SizedBox(),
        _keypadButton('0', isDark, isVideoActive,
            fontSize: buttonFontSize, backspaceIconSize: backspaceIconSize),
        _keypadButton('backspace', isDark, isVideoActive,
            isAction: true,
            fontSize: buttonFontSize,
            backspaceIconSize: backspaceIconSize),
      ],
    );
  }

  Widget _keypadButton(String label, bool isDark, bool isVideoActive,
      {bool isAction = false,
      double fontSize = 16,
      double backspaceIconSize = 16}) {
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
          if (_otpController.text.length < 4) {
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
                  size: backspaceIconSize,
                  color: isDark ? Colors.white38 : Colors.black38)
              : Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
        ),
      ),
    );
  }
}
