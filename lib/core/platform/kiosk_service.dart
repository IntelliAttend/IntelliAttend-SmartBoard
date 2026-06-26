import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/logger.dart';
import '../../services/session_manager.dart';

enum KioskMode {
  /// Fullscreen mode with no kiosk locks. Used for Registration, Idle, and
  /// timetable screens. The window fills the display and stays on top of the
  /// taskbar so nothing overlaps on the kiosk display.
  fullscreen,

  /// Locked: Active attendance session (PIN entry phase). Fullscreen,
  /// always-on-top, close blocked, taskbar hidden. User may still minimize
  /// — the app stays active in the background fetching session data.
  locked,



  /// Suspended: Minimized between sessions by the orchestrator.
  suspended,
}

class KioskService {
  /// Platform channel to the C++ runner.  Tells the native side whether
  /// to absorb WM_SYSCOMMAND SC_CLOSE/SC_MAXIMIZE in the message pump.
  /// When kiosk hardening is active these are blocked; when not active
  /// (boot, suspended, or force-released) they pass through so the user
  /// can close the window via Alt+F4 or the taskbar.
  static const _kioskChannel = MethodChannel('com.intelliattend/kiosk');

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
        Log.w(
            '🛡️ [Kiosk] Health check: window not fullscreen. Re-applying $mode.');
        await setMode(mode, force: true);
      }
    } catch (e) {
      Log.d('[Kiosk] Health check failed: $e');
    }
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
      try {
        await prior;
      } catch (e) {
        Log.d('[Kiosk] Prior operation failed (clearing): $e');
      }
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
      Log.w(
          '🔄 [Kiosk] Re-entrant _applyMode($mode) — skipping (already applying).');
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

        // ── SUSPENDED ────────────────────────────────────────────────────────
        case KioskMode.suspended:
          // Remember the mode we're suspending from so onWindowRestore can
          // restore fullscreen with the correct mode.
          _preSuspendMode = _currentMode;
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager
              .setResizable(true); // Allow resizing when suspended
          if (Platform.isWindows) {
            // CRITICAL: Keep close prevented even when minimized — otherwise
            // the taskbar context menu "Close window" bypasses kiosk locks.
            await windowManager.setPreventClose(true);
            // Show icon on taskbar when minimized so user knows it's alive.
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.minimize();
          break;
      }

      _currentMode = mode;

      // Sync the C++ blocking flags with the current mode.
      // close_blocked_ is always active during any kiosk mode (including
      // suspended) so the window cannot be killed from the taskbar.
      //   block_sys_commands_ blocks SC_MAXIMIZE during fullscreen/locked
      //   but is released during suspended so the user can
      //   restore the window from the taskbar.
      if (Platform.isWindows) {
        switch (mode) {
          case KioskMode.fullscreen:
          case KioskMode.locked:
            await _setBlockSysCommands(true);
            await _setBlockCloseCommands(true);
            break;
          case KioskMode.suspended:
            await _setBlockSysCommands(false);
            await _setBlockCloseCommands(true);
            break;
        }
      }
    } catch (e) {
      Log.e('❌ [Kiosk] setMode($mode) failed: $e');
    } finally {
      _isApplyingMode = false;
    }
  }

  /// Tells the C++ runner whether to absorb WM_SYSCOMMAND SC_MAXIMIZE.
  static Future<void> _setBlockSysCommands(bool block) async {
    try {
      await _kioskChannel.invokeMethod('setBlockSysCommands', block);
    } catch (e) {
      Log.d('[Kiosk] setBlockSysCommands($block) failed: $e');
    }
  }

  /// Tells the C++ runner whether to absorb WM_CLOSE and WM_SYSCOMMAND
  /// SC_CLOSE at the native message-pump level.  This flag stays true
  /// whenever kiosk hardening is active (fullscreen, locked,
  /// AND suspended) so the window cannot be killed from the taskbar context
  /// menu or via Alt+F4 while minimized.  Only set to false by
  /// [forceRelease] or during early boot.
  static Future<void> _setBlockCloseCommands(bool block) async {
    try {
      await _kioskChannel.invokeMethod('setBlockCloseCommands', block);
    } catch (e) {
      Log.d('[Kiosk] setBlockCloseCommands($block) failed: $e');
    }
  }

  /// Administrative escape door — performs a cascading teardown and
  /// terminates the application cleanly.  Releases kiosk constraints,
  /// flushes the local Isar database, then destroys the native window.
  /// If windowManager fails, falls back to exit(0).
  static Future<void> executeAdministrativeShutdown() async {
    try {
      Log.w('🛑 [Kiosk] Administrative Kill Switch Triggered. Initializing Teardown...');
      await forceRelease();
      try {
        await SessionManager.isar.close();
      } catch (_) {
        Log.d('[Kiosk] Isar already closed or unavailable.');
      }
      await windowManager.destroy();
    } catch (e) {
      Log.e('❌ [Kiosk] Administrative shutdown fallback: $e');
      exit(0);
    }
  }

  /// Force-releases all kiosk constraints, making the window a normal
  /// closable window with a visible taskbar icon. This is the emergency
  /// kill switch — call it when the app freezes or the user needs to
  /// close the window.
  static Future<void> forceRelease() async {
    Log.w('🛑 [Kiosk] FORCE RELEASE');
    _enabled = false;
    _currentMode = null;
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.setPreventClose(false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setFullScreen(false);
      await windowManager.setResizable(true);
      await windowManager.show();
      if (Platform.isWindows) {
        await _setBlockSysCommands(false);
        await _setBlockCloseCommands(false);
      }
    } catch (e) {
      Log.e('❌ [Kiosk] forceRelease error: $e');
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

/// Listens for window restore/minimize/close events and enforces kiosk mode.
class _KioskWindowListener extends WindowListener {
  @override
  void onWindowRestore() {
    _enforceOnRestore();
  }

  @override
  void onWindowClose() {
    // Defense-in-depth: if the C++ layer somehow misses a close message
    // (e.g. plugin race during startup), this prevents the Dart layer
    // from forwarding it while kiosk is active.
    if (KioskService._enabled && KioskService._currentMode != null) {
      Log.w('🛡️ [Kiosk] onWindowClose intercepted — kiosk active, ignoring.');
      return;
    }
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
    // No-op: minimize is always allowed in current modes.
  }
}
