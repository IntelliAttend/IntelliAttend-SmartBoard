#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// Unhandled exception filter: called when any unhandled C++ or structured
// exception escapes the Flutter message loop. Shows a friendly error so the
// user sees a dialog instead of a frozen desktop, then lets the OS terminate
// the process naturally. DWM recovers because the window is a normal
// overlapped window (not WS_POPUP fullscreen) during plugin init.
static LONG WINAPI
TopLevelExceptionFilter(EXCEPTION_POINTERS *ep) noexcept {
  const DWORD code = ep->ExceptionRecord->ExceptionCode;
  const wchar_t *desc;

  switch (code) {
    case 0xE06D7363:  // MSVC C++ exception (e.g. from cloud_firestore SDK)
      desc = L"A native plugin component encountered an error and needs to "
             L"close. Please restart the application.";
      break;
    case EXCEPTION_ACCESS_VIOLATION:
      desc = L"The application attempted to access invalid memory.";
      break;
    default:
      desc = L"An unexpected system-level error occurred.";
      break;
  }

  ::MessageBoxW(nullptr, desc,
                L"IntelliAttend SmartBoard — Unexpected Error",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);

  return EXCEPTION_EXECUTE_HANDLER;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Register a top-level exception filter BEFORE any Flutter initialization
  // so that C++ exceptions thrown by native plugin code (e.g. cloud_firestore
  // C++ SDK) are caught and shown to the user instead of silently terminating
  // the process. Combined with the WS_OVERLAPPEDWINDOW window style change,
  // this ensures DWM recovers the desktop properly on crash.
  ::SetUnhandledExceptionFilter(TopLevelExceptionFilter);

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"intelliattend_smartboard", origin, size)) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
