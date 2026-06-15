# Kiosk Security Hardening

**Date:** 2026-06-13  
**Scope:** Windows desktop kiosk — anti-tamper, build cleanup, administrative escape  
**Context:** SmartBoard runs as a fullscreen kiosk in exam rooms. Students must not be able to close or minimise the application through any standard OS affordance.

---

## 1. Threat Model & Attack Vectors

| Vector | User Action | Intercepted By |
|---|---|---|
| Alt+F4 | Keyboard shortcut | C++ `WM_SYSCOMMAND SC_CLOSE` |
| Close button (X) | Mouse click on title bar | C++ `WM_SYSCOMMAND SC_CLOSE` |
| Taskbar right-click → "Close window" | Context menu on taskbar icon | C++ `WM_CLOSE` |
| Task Manager → "End Task" | Processes tab → End task | C++ `WM_CLOSE` |
| Minimise → restore via taskbar | Click taskbar icon while suspended | C++ `SC_MAXIMIZE` controlled by mode |
| `taskkill /F /IM ...` | Admin command prompt | **Not interceptable** — OS-level |

---

## 2. Architecture (Three Defense Layers)

### Layer 1 — Native C++ Win32 Message Pump (`windows/runner/flutter_window.cpp`, `flutter_window.h`)

Two independent boolean flags control message absorption **before** Flutter or `window_manager` sees the event:

- **`close_blocked_`** — traps `WM_CLOSE` and `WM_SYSCOMMAND SC_CLOSE` unconditionally. Stays `true` during all kiosk modes including `suspended` (minimised) so the taskbar context menu "Close window" cannot kill the app while minimised.
- **`block_sys_commands_`** — traps `SC_MAXIMIZE` only. `false` during `suspended` so the user can restore the window from the taskbar. `true` during `fullscreen` / `locked` / `absoluteLocked` so the window cannot be restored while the kiosk is active.

Both default to `false` so boot / registration / failure screens remain closable.

A new method channel handler `setBlockCloseCommands(bool)` was added alongside the existing `setBlockSysCommands(bool)`.

### Layer 2 — Dart Platform Channel (`lib/core/platform/kiosk_service.dart`)

`_applyMode()` calls both setters on every mode transition:

| Kiosk Mode | `setBlockCloseCommands` | `setBlockSysCommands` |
|---|---|---|
| `fullscreen` | `true` | `true` |
| `locked` | `true` | `true` |
| `absoluteLocked` | `true` | `true` |
| `suspended` | `true` | `false` |

`forceRelease()` sets both to `false`, restoring normal window behaviour.

### Layer 3 — Dart `onWindowClose()` Override (`_KioskWindowListener`)

Defense-in-depth: returns early if kiosk is enabled, preventing the `window_manager` plugin from forwarding the close event up to Dart-level handlers.

---

## 3. Administrative Escape Routes

| Method | How |
|---|---|
| `Ctrl+Shift+J × 3` | In-app kill switch — calls `KioskService.executeAdministrativeShutdown()` |
| `taskkill /F /IM intelliattend_smartboard.exe /T` | OS-level — bypasses all interception (recommended for remote admin) |

`executeAdministrativeShutdown()` performs a cascading teardown:
1. `KioskService.forceRelease()` — releases all kiosk constraints and sets both C++ flags to `false`
2. `SessionManager.isar.close()` — cleanly closes the local Isar database
3. `windowManager.destroy()` — destroys the native window
4. Falls back to `exit(0)` if window destruction fails

---

## 4. Build Cleanup

### LNK4099 Suppression (`windows/runner/CMakeLists.txt`)

The Firebase C++ Desktop SDK (`firebase_app.lib`) was compiled against `libcurl-d.pdb`, which Google does not ship. This produced cosmetic `LNK4099` warnings during every debug build.

```
if(MSVC)
    target_link_options(${BINARY_NAME} PRIVATE "/ignore:4099")
endif()
```

The `/ignore:4099` linker flag suppresses these warnings. Build output is now pristine — zero warnings.

---

## 5. Additional Fixes

- **`InitFailureScreen` close button**: replaced `SystemNavigator.pop()` (no-op on Windows) with `windowManager.destroy()`.
- **Removed dead code**: unused imports and manual cleanup from `attendance_screen.dart` kill switch — delegated entirely to `executeAdministrativeShutdown()`.
- **Global kill switch**: `main.dart` now calls `executeAdministrativeShutdown()` instead of `forceRelease()` + navigation to `BootScreen`.

---

## 6. Key Files

| File | Role |
|---|---|
| `windows/runner/flutter_window.h` | Declares `close_blocked_` and `block_sys_commands_` flags |
| `windows/runner/flutter_window.cpp` | Win32 message handler + method channel registration |
| `windows/runner/CMakeLists.txt` | `/ignore:4099` linker flag |
| `lib/core/platform/kiosk_service.dart` | All Dart-side kiosk hardening, `_applyMode()`, `executeAdministrativeShutdown()`, `forceRelease()` |
| `lib/main.dart` | Global `Ctrl+Shift+J` kill switch |
| `lib/presentation/screens/attendance_screen.dart` | Attendance screen kill switch |
| `lib/presentation/screens/init_failure_screen.dart` | Uses `windowManager.destroy()` |

---

## 7. Verification

- `flutter analyze` — zero errors (pre-existing `local_plugins/` test warnings unrelated)
- `flutter build windows --debug` — zero warnings, zero errors
- App launches, kiosk mode activates, all close vectors blocked, `Ctrl+Shift+J` escape works
