#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Platform channel for kiosk communication with Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> kiosk_channel_;

  // When true, WM_CLOSE and WM_SYSCOMMAND SC_CLOSE are absorbed at the
  // native message-pump level, making the window unkillable from the
  // taskbar context menu, Alt+F4, or the X button regardless of focus
  // or visibility state.  Managed independently of block_sys_commands_
  // so that close remains blocked even when the window is minimized
  // (suspended) but maximize is still allowed.
  //
  // Defaults to false so the boot/registration screen remains closable.
  bool close_blocked_ = false;

  // When true, WM_SYSCOMMAND SC_MAXIMIZE is absorbed, preventing the
  // window from being restored from the taskbar during kiosk hardening.
  // This is set to false during suspended mode so the user can restore
  // the window, and to true during fullscreen/locked/absoluteLocked.
  //
  // Defaults to false so the window starts in a normal resizable state.
  bool block_sys_commands_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
