#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>
#include <wchar.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kCrashFlagFile[] =
    L"intelliattend_smartboard_native_engine_crash.flag";

std::wstring CrashFlagPath() {
  wchar_t temp_path[MAX_PATH];
  const DWORD length = ::GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) {
    return kCrashFlagFile;
  }
  return std::wstring(temp_path) + kCrashFlagFile;
}

void WriteNativeCrashFlag(DWORD code) {
  const std::wstring path = CrashFlagPath();
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  char buffer[64];
  const int length =
      std::snprintf(buffer, sizeof(buffer), "exception=0x%08lx\r\n", code);
  DWORD written = 0;
  ::WriteFile(file, buffer, static_cast<DWORD>(length), &written, nullptr);
  ::CloseHandle(file);
}

bool NativeCrashFlagExists() {
  return ::GetFileAttributesW(CrashFlagPath().c_str()) !=
         INVALID_FILE_ATTRIBUTES;
}

void ClearNativeCrashFlag() {
  ::DeleteFileW(CrashFlagPath().c_str());
}

bool HasArgument(const std::vector<std::string>& args,
                 const std::string& name) {
  return std::find(args.begin(), args.end(), name) != args.end();
}

bool EnvEquals(const wchar_t* name, const wchar_t* value) {
  wchar_t buffer[64];
  const DWORD length = ::GetEnvironmentVariableW(name, buffer, 64);
  return length > 0 && _wcsicmp(buffer, value) == 0;
}

}  // namespace

// Unhandled exception filter: called when any unhandled C++ or structured
// exception escapes the Flutter message loop. Shows a friendly error so the
// user sees a dialog instead of a frozen desktop, then lets the OS terminate
// the process naturally. DWM recovers because the window is a normal
// overlapped window (not WS_POPUP fullscreen) during plugin init.
static LONG WINAPI
TopLevelExceptionFilter(EXCEPTION_POINTERS *ep) noexcept {
  const DWORD code = ep->ExceptionRecord->ExceptionCode;
  const wchar_t *desc;

  WriteNativeCrashFlag(code);

  switch (code) {
    case 0xc000041d:
      desc = L"The Flutter rendering engine failed while starting. "
             L"IntelliAttend will try GPU compatibility mode on the next "
             L"launch. If this repeats, update the app build and Intel GPU "
             L"driver, or contact IntelliAttend support.";
      break;
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
                L"IntelliAttend SmartBoard - Startup Error",
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

  const bool native_crash_recovery = NativeCrashFlagExists();
  const bool force_low_power_gpu =
      native_crash_recovery ||
      HasArgument(command_line_arguments, "--intelliattend-low-power-gpu") ||
      EnvEquals(L"INTELLIATTEND_GPU_MODE", L"low_power");

  if (force_low_power_gpu) {
    project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);
    if (!HasArgument(command_line_arguments, "--native-crash-recovery")) {
      command_line_arguments.push_back("--native-crash-recovery");
    }
  }

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

  ClearNativeCrashFlag();
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
