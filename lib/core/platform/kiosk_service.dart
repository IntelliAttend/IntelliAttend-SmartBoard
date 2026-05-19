import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:window_manager/window_manager.dart';
import '../utils/logger.dart';
import 'hardware_fingerprint_service.dart';

enum KioskMode {
  /// Fullscreen mode with no kiosk locks. Used for Registration, Idle, and
  /// timetable screens. The window fills the display and stays on top of the
  /// taskbar so nothing overlaps on the kiosk display.
  fullscreen,

  /// Locked: Active attendance session (PIN entry phase). Fullscreen,
  /// always-on-top, close blocked, taskbar hidden. User may still minimize
  /// — the app stays active in the background fetching session data.
  locked,

  /// AbsoluteLocked: QR scanning phase. Same as locked PLUS:
  ///   - Minimize is intercepted and blocked (window jumps back to fullscreen)
  ///   - Display brightness forced to 100%
  ///   - Screen capture (screenshot/recording/share) blocked via WDA_MONITOR
  ///   - No escape until session ends or capacity reached.
  absoluteLocked,

  /// Suspended: Minimized between sessions by the orchestrator.
  suspended,
}

class KioskService {
  static bool _enabled = false;
  // Use a sentinel value so the very first setMode() call always applies.
  static KioskMode? _currentMode;

  /// Remembers the mode that was active before the user minimized the window
  /// to `suspended`. When the window is restored from the taskbar,
  /// `onWindowRestore` uses this to re-apply fullscreen with the correct mode.
  static KioskMode? _preSuspendMode;

  // Serialises setMode() calls so concurrent callers (e.g. the
  // WindowOrchestratorService timer firing while IdleScreen's post-frame
  // callback runs) cannot issue overlapping window_manager native calls.
  // Two concurrent setFullScreen / setAlwaysOnTop calls on Windows crash
  // the Flutter engine silently.
  static Future<void>? _inFlight;

  /// Periodic watchdog that re-enforces fullscreen in case any edge case
  /// causes the window to leave fullscreen (e.g. monitor hotplug, DPI
  /// change, or a missed restore event).
  static Timer? _fullscreenWatchdog;

  static void enable() {
    if (!Platform.isWindows) return;
    if (_enabled) return;
    _enabled = true;

    // Re-apply fullscreen whenever the window is restored from minimize.
    // Without this, minimizing a fullscreen window and clicking the taskbar
    // icon restores it as a normal windowed frame—not fullscreen.
    windowManager.addListener(_KioskWindowListener());
    _startFullscreenWatchdog();
    Log.i('🛡️ [Kiosk] Kiosk hardening enabled');
  }

  /// Starts a periodic timer (every 10s) that checks if the window is in
  /// fullscreen when it should be. If not, it re-applies the current mode.
  /// This is a safety net for edge cases (monitor hotplug, missed restore
  /// events, DPI changes, etc.).
  static void _startFullscreenWatchdog() {
    _fullscreenWatchdog?.cancel();
    _fullscreenWatchdog = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        if (!_enabled) return;
        final mode = _currentMode;
        if (mode == null || mode == KioskMode.suspended) return;
        try {
          final full = await windowManager.isFullScreen();
          if (!full) {
            Log.w('🛡️ [Kiosk] Watchdog: window not fullscreen. Re-applying $mode.');
            await setMode(mode);
          }
        } catch (_) {}
      },
    );
  }

  // ---------------------------------------------------------------------------
  // setMode — the central state machine.
  //
  // NOTE: We intentionally do NOT skip when mode == _currentMode. Every call
  // re-applies the window state so a crash/recovery or dual-monitor hotplug
  // always restores the correct fullscreen state.
  // ---------------------------------------------------------------------------
  static Future<void> setMode(KioskMode mode) async {
    // Serialise so a second caller waits for the first to fully finish before
    // issuing any window_manager native calls.
    final prior = _inFlight;
    final completer = Completer<void>();
    _inFlight = completer.future;
    if (prior != null) {
      try { await prior; } catch (_) {}
    }
    try {
      await _applyMode(mode);
    } finally {
      completer.complete();
      if (identical(_inFlight, completer.future)) {
        _inFlight = null;
      }
    }
  }

  static Future<void> _applyMode(KioskMode mode) async {
    final prev = _currentMode;
    Log.i('🔄 [Kiosk] setMode($mode) [was $prev]');

    try {
      switch (mode) {
        // ── FULLSCREEN ────────────────────────────────────────────────────────
        case KioskMode.fullscreen:
          await windowManager.setResizable(false);
          await windowManager.setAlwaysOnTop(true);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.setFullScreen(true);
          break;

        // ── LOCKED ───────────────────────────────────────────────────────────
        case KioskMode.locked:
          await windowManager.setResizable(false);
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            await windowManager.setSkipTaskbar(true);
          }
          break;

        // ── ABSOLUTE LOCKED (QR scanning) ──────────────────────────────────
        case KioskMode.absoluteLocked:
          await windowManager.setResizable(false);
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            await windowManager.setSkipTaskbar(true);
          }
          await _maximizeBrightness();
          await _preventScreenCapture();
          break;

        // ── SUSPENDED ────────────────────────────────────────────────────────
        case KioskMode.suspended:
          // Remember the mode we're suspending from so onWindowRestore can
          // restore fullscreen with the correct mode when the user clicks the
          // taskbar icon.
          _preSuspendMode = _currentMode;
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager.setResizable(false);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.minimize();
          break;
      }

      // Restore screen capture when leaving absoluteLocked
      if (prev == KioskMode.absoluteLocked && mode != KioskMode.absoluteLocked) {
        await _allowScreenCapture();
      }

      _currentMode = mode;
    } catch (e) {
      Log.e('❌ [Kiosk] setMode($mode) failed: $e');
    }
  }

  static Future<void> _maximizeBrightness() async {
    try {
      await HardwareFingerprintService.maximizeBrightness();
      Log.i('💡 [Kiosk] Display brightness set to 100%.');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Brightness set failed: $e');
    }
  }

  static Future<void> _preventScreenCapture() async {
    try {
      await HardwareFingerprintService.preventScreenCapture();
      Log.i('🛡️ [Kiosk] Screen capture blocked (WDA_MONITOR).');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Screen capture prevention failed: $e');
    }
  }

  static Future<void> _allowScreenCapture() async {
    try {
      await HardwareFingerprintService.allowScreenCapture();
      Log.i('🛡️ [Kiosk] Screen capture restored (WDA_NONE).');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Screen capture restore failed: $e');
    }
  }

  static KioskMode? get currentMode => _currentMode;
  static bool get isEnabled => _enabled;

  /// Creates a window listener instance for testing. The listener has no local
  /// state — it reads/writes [KioskService]'s static fields directly, so a
  /// fresh instance behaves identically to the one registered by [enable].
  @visibleForTesting
  static WindowListener createWindowListener() => _KioskWindowListener();
}

/// Listens for window restore/minimize events and enforces kiosk mode.
class _KioskWindowListener extends WindowListener {
  @override
  void onWindowRestore() {
    _enforceOnRestore();
  }

  /// Re-applies fullscreen after window restore. The underlying
  /// [windowManager.setFullScreen] call from [KioskService.setMode] works
  /// reliably here because the method channel provides a natural async
  /// boundary — the window has already finished its OS restore transition
  /// by the time the Dart handler executes.
  static Future<void> _enforceOnRestore() async {
    final mode = KioskService.currentMode;
    if (mode == KioskMode.suspended) {
      await KioskService.setMode(
          KioskService._preSuspendMode ?? KioskMode.fullscreen);
    } else if (mode != null) {
      await KioskService.setMode(mode);
    }
  }

  @override
  void onWindowMinimize() {
    final mode = KioskService.currentMode;
    if (mode == KioskMode.absoluteLocked) {
      // QR scanning phase — window is not allowed to minimize.
      // Immediately restore fullscreen.
      KioskService.setMode(KioskMode.absoluteLocked);
    }
  }
}
