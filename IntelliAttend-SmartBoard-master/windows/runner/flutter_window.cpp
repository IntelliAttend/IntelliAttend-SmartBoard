#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // ── Register kiosk platform channel ─────────────────────────────────────
  // Listens for setBlockSysCommands from Dart so WM_CLOSE and
  // WM_SYSCOMMAND SC_CLOSE/SC_MAXIMIZE absorption can be toggled based
  // on kiosk hardening state.
  kiosk_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.intelliattend/kiosk",
      &flutter::StandardMethodCodec::GetInstance());

  kiosk_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setBlockSysCommands") {
          if (call.arguments() && std::holds_alternative<bool>(*call.arguments())) {
            block_sys_commands_ = std::get<bool>(*call.arguments());
          }
          result->Success();
        } else if (call.method_name() == "setBlockCloseCommands") {
          if (call.arguments() && std::holds_alternative<bool>(*call.arguments())) {
            close_blocked_ = std::get<bool>(*call.arguments());
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // ── Kiosk: absorb close messages before Flutter/plugins see them ─────
  // close_blocked_ traps WM_CLOSE (taskbar right-click → Close window,
  // End Task) and WM_SYSCOMMAND SC_CLOSE (Alt+F4, X button)
  // unconditionally.  This flag stays true during suspended (minimized)
  // mode so the window cannot be killed from the taskbar.
  //
  // block_sys_commands_ traps SC_MAXIMIZE only — it is false during
  // suspended so the user can restore the window, and true during
  // fullscreen / locked / absoluteLocked to prevent taskbar restore.
  //
  // Both flags default to false so the boot / registration / failure
  // screens remain fully closable.
  if (close_blocked_) {
    switch (message) {
      case WM_CLOSE:
        return 0;
      case WM_SYSCOMMAND: {
        const auto cmd = wparam & 0xFFF0;
        if (cmd == SC_CLOSE) {
          return 0;
        }
        break;
      }
    }
  }
  if (block_sys_commands_) {
    switch (message) {
      case WM_SYSCOMMAND: {
        const auto cmd = wparam & 0xFFF0;
        if (cmd == SC_MAXIMIZE) {
          return 0;
        }
        break;
      }
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window
  // messages.  WM_CLOSE and SC_CLOSE will never reach this point when
  // block_sys_commands_ is true.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                       lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
