import 'dart:io';
import 'dart:ui' show Rect, Offset;
import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../utils/logger.dart';

enum KioskMode {
  /// Open: True OS fullscreen, no kiosk locks. Used for the Registration screen.
  /// The admin can still close (Alt+F4 / Exit button) and Alt+Tab, but the
  /// window fills every pixel and cannot be resized.
  open,

  /// Soft: True OS fullscreen, no kiosk locks. Used for the Idle/timetable
  /// screen between classes. Faculty can bring other windows over it but the
  /// board itself always fills the display.
  soft,

  /// Locked: Active attendance session. Fullscreen, always-on-top, close
  /// blocked, taskbar hidden, brightness maximised for QR scanning.
  locked,

  /// Suspended: Minimized between sessions by the orchestrator.
  suspended,
}

class KioskService {
  static bool _enabled = false;
  // Use a sentinel value so the very first setMode() call always applies.
  static KioskMode? _currentMode;
  static double _originalBrightness = 1.0;
  static bool _hasSavedBrightness = false;

  static void enable() {
    if (!Platform.isWindows) return;
    if (_enabled) return;
    _enabled = true;
    Log.i('🛡️ [Kiosk] Kiosk hardening enabled');
  }

  // ---------------------------------------------------------------------------
  // coverActiveScreen
  // Uses screen_retriever to find which physical display the window is on
  // and calls setFullScreen(true). On any error falls back gracefully.
  // ---------------------------------------------------------------------------
  static Future<void> coverActiveScreen() async {
    if (kIsWeb) return;
    try {
      final winBounds = await windowManager.getBounds();
      final winCx = winBounds.left + winBounds.width / 2;
      final winCy = winBounds.top + winBounds.height / 2;

      final displays = await screenRetriever.getAllDisplays();
      Display? target;

      for (final d in displays) {
        final pos = d.visiblePosition ?? Offset.zero;
        final sz = d.visibleSize ?? d.size;
        if (winCx >= pos.dx &&
            winCx < pos.dx + sz.width &&
            winCy >= pos.dy &&
            winCy < pos.dy + sz.height) {
          target = d;
          break;
        }
      }
      target ??= await screenRetriever.getPrimaryDisplay();

      final pos = target.visiblePosition ?? Offset.zero;
      final sz = target.visibleSize ?? target.size;

      Log.i('🖥️ [Kiosk] Identified display "${target.name ?? target.id}" '
          '${sz.width.toInt()}×${sz.height.toInt()} '
          'at (${pos.dx.toInt()}, ${pos.dy.toInt()})');
    } catch (e) {
      Log.w('⚠️ [Kiosk] coverActiveScreen probe failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // setMode — the central state machine.
  //
  // NOTE: We intentionally do NOT skip when mode == _currentMode. Every call
  // re-applies the window state so a crash/recovery or dual-monitor hotplug
  // always restores the correct fullscreen state.
  // ---------------------------------------------------------------------------
  static Future<void> setMode(KioskMode mode) async {
    final prev = _currentMode;
    Log.i('🔄 [Kiosk] setMode($mode) [was $prev]');

    try {
      switch (mode) {
        // ── OPEN ─────────────────────────────────────────────────────────────
        // Registration screen. True OS fullscreen so every pixel is covered.
        // Not locked: Alt+F4, Exit button, and Alt+Tab all work.
        case KioskMode.open:
          await windowManager.setResizable(false);
          await windowManager.setAlwaysOnTop(false);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.setFullScreen(true);
          await _restoreBrightness();
          break;

        // ── SOFT ─────────────────────────────────────────────────────────────
        // Idle board between classes. True OS fullscreen, closeable.
        case KioskMode.soft:
          await windowManager.setResizable(false);
          await windowManager.setAlwaysOnTop(false);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.setFullScreen(true);
          await _restoreBrightness();
          break;

        // ── LOCKED ───────────────────────────────────────────────────────────
        // Active attendance session: fullscreen, always on top, close blocked,
        // taskbar hidden, brightness maximised so QR is readable at a distance.
        case KioskMode.locked:
          if (prev != KioskMode.locked) {
            await _saveBrightness();
          }
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
          break;

        // ── SUSPENDED ────────────────────────────────────────────────────────
        // Orchestrator-triggered minimise. Restore window to non-fullscreen
        // first so Windows positions the restored window correctly.
        case KioskMode.suspended:
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager.setResizable(false);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.minimize();
          await _restoreBrightness();
          break;
      }

      _currentMode = mode;
    } catch (e) {
      Log.e('❌ [Kiosk] setMode($mode) failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Brightness helpers
  // ---------------------------------------------------------------------------
  static Future<void> _saveBrightness() async {
    try {
      _originalBrightness = await ScreenBrightness().application;
      _hasSavedBrightness = true;
      Log.i('🔅 [Kiosk] Saved brightness: ${(_originalBrightness * 100).toInt()}%');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to save brightness: $e');
    }
  }

  static Future<void> _maximizeBrightness() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
      Log.i('🔆 [Kiosk] Max brightness set for QR visibility.');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to set max brightness: $e');
    }
  }

  static Future<void> _restoreBrightness() async {
    if (!_hasSavedBrightness) return;
    try {
      await ScreenBrightness().setApplicationScreenBrightness(_originalBrightness);
      _hasSavedBrightness = false;
      Log.i('🔅 [Kiosk] Restored brightness: ${(_originalBrightness * 100).toInt()}%');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to restore brightness: $e');
    }
  }

  static KioskMode? get currentMode => _currentMode;
  static bool get isEnabled => _enabled;
}
