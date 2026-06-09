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
  // Listens for setBlockSysCommands from Dart so WM_SYSCOMMAND SC_CLOSE
  // absorption can be toggled based on kiosk hardening state.
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
  // Give Flutter, including plugins, an opportunity to handle window messages.
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

    // ── Kiosk: conditionally block window-close system commands ────────────
    // When kiosk hardening is active (block_sys_commands_ == true), we
    // intercept SC_CLOSE and SC_MAXIMIZE so Alt+F4 / the close button /
    // maximize cannot be used.  When not active (boot phase, suspended, or
    // force-released), these pass through to DefWindowProc so the
    // window_manager plugin's WM_CLOSE handler (setPreventClose) controls
    // close behaviour — keeping the taskbar "Close" option and Alt+F4
    // available when the user needs to close the app.
    case WM_SYSCOMMAND: {
      if (block_sys_commands_) {
        const auto cmd = wparam & 0xFFF0;
        if (cmd == SC_CLOSE || cmd == SC_MAXIMIZE) {
          return 0; // Absorb — do not forward to DefWindowProc.
        }
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
