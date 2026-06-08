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
  static bool _screenCaptureFailed = false;

  static final StreamController<bool> _screenCapController =
      StreamController<bool>.broadcast();
  static Stream<bool> get onScreenCaptureWarning => _screenCapController.stream;
  static bool get isScreenCaptureCompromised => _screenCaptureFailed;

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

  // Guards against re-entrant _applyMode calls when a window_manager native
  // call (e.g. setFullScreen) triggers a window event (onWindowRestore)
  // that itself calls setMode. Without this guard, the window listener
  // would queue a redundant re-apply, wasting platform channel calls.
  static bool _isApplyingMode = false;

  static void enable() {
    if (!Platform.isWindows) return;
    if (_enabled) return;
    _enabled = true;

    // Re-apply fullscreen whenever the window is restored from minimize.
    // Without this, minimizing a fullscreen window and clicking the taskbar
    // icon restores it as a normal windowed frame—not fullscreen.
    windowManager.addListener(_KioskWindowListener());
    Log.i('🛡️ [Kiosk] Kiosk hardening enabled');
  }

  /// Checks whether the window is currently in the expected fullscreen state
  /// and re-applies the current mode if not. This is called from
  /// [WindowOrchestratorService]'s single periodic tick so there is exactly
  /// one timer source checking window health — preventing the concurrent
  /// platform-channel call storm that caused system-wide DWM freezes.
  static Future<void> ensureFullscreen() async {
    if (!_enabled) return;
    final mode = _currentMode;
    if (mode == null || mode == KioskMode.suspended) return;
    try {
      final full = await windowManager.isFullScreen();
      if (!full) {
        Log.w('🛡️ [Kiosk] Health check: window not fullscreen. Re-applying $mode.');
        await setMode(mode, force: true);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // setMode — the central state machine.
  //
  // When [force] is false (default) and [mode] matches the cached [_currentMode],
  // we check the actual window state via [windowManager.isFullScreen] before
  // applying. This eliminates redundant platform-channel calls that were
  // causing concurrent-call crashes and DWM freezes on Windows.
  //
  // Pass [force: true] only when a crash recovery or monitor-hotplug scenario
  // genuinely requires re-application (e.g. [ensureFullscreen]).
  // ---------------------------------------------------------------------------
  static Future<void> setMode(KioskMode mode, {bool force = false}) async {
    // Skip re-apply if mode hasn't changed and we can verify the window is
    // already in the correct state.  Always apply on first call (sentinel).
    if (!force && _currentMode != null && mode == _currentMode) {
      if (mode == KioskMode.suspended) {
        // For suspended we trust the cached state — no way to check.
        return;
      }
      try {
        final isFull = await windowManager.isFullScreen();
        if (isFull) return;
      } catch (_) {
        // Platform channel unavailable; proceed to re-apply defensively.
      }
    }

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
    if (_isApplyingMode) {
      Log.w('🔄 [Kiosk] Re-entrant _applyMode($mode) — skipping (already applying).');
      return;
    }
    _isApplyingMode = true;

    final prev = _currentMode;
    Log.i('🔄 [Kiosk] setMode($mode) [was $prev]');

    try {
      switch (mode) {
        // ── FULLSCREEN ────────────────────────────────────────────────────────
        case KioskMode.fullscreen:
          await windowManager.setResizable(false);
          // alwaysOnTop BEFORE show/focus so the window is already on-top
          // when it becomes visible — prevents taskbar flash during restore.
          await windowManager.setAlwaysOnTop(true);
          await windowManager.show();
          await windowManager.focus();
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            // Skip taskbar entirely in fullscreen — app never appears on the taskbar.
            await windowManager.setSkipTaskbar(true);
          }
          await windowManager.setFullScreen(true);
          break;

        // ── LOCKED (deprecated — superseded by fullscreen with skipTaskbar) ──
        case KioskMode.locked:
          // Fall through to fullscreen behaviour.
          await windowManager.setResizable(false);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.show();
          await windowManager.focus();
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            await windowManager.setSkipTaskbar(true);
          }
          await windowManager.setFullScreen(true);
          break;

        // ── ABSOLUTE LOCKED (QR scanning) ──────────────────────────────────
        case KioskMode.absoluteLocked:
          await windowManager.setResizable(false);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
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
          // restore fullscreen with the correct mode.
          _preSuspendMode = _currentMode;
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager.setResizable(true); // Allow resizing when suspended
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            // Show icon on taskbar when minimized so user knows it's alive.
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.minimize();
          break;
      }

      // Restore screen capture + brightness when leaving absoluteLocked
      if (prev == KioskMode.absoluteLocked && mode != KioskMode.absoluteLocked) {
        await _allowScreenCapture();
        await _restoreBrightness();
      }

      _currentMode = mode;
    } catch (e) {
      Log.e('❌ [Kiosk] setMode($mode) failed: $e');
    } finally {
      _isApplyingMode = false;
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

  static Future<void> _restoreBrightness() async {
    try {
      await HardwareFingerprintService.restoreBrightness();
      Log.i('💡 [Kiosk] Display brightness restored.');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Brightness restore failed: $e');
    }
  }

  static Future<void> _preventScreenCapture() async {
    try {
      await HardwareFingerprintService.preventScreenCapture();
      _screenCaptureFailed = false;
      _screenCapController.add(false);
      Log.i('🛡️ [Kiosk] Screen capture blocked (WDA_MONITOR).');
    } catch (e) {
      _screenCaptureFailed = true;
      _screenCapController.add(true);
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

  /// Re-applies fullscreen after window restore. Skips if we are already
  /// in the middle of [_applyMode] so a platform-channel call like
  /// [windowManager.setFullScreen] cannot trigger a re-entrant apply loop
  /// that freezes the Windows message pump.
  static Future<void> _enforceOnRestore() async {
    if (KioskService._isApplyingMode) return;

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
