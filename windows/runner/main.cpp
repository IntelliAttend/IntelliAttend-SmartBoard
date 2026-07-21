#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
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

bool ContainsCaseInsensitive(const std::wstring& value,
                             const std::wstring& needle) {
  std::wstring haystack = value;
  std::wstring lowered_needle = needle;
  std::transform(haystack.begin(), haystack.end(), haystack.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  std::transform(lowered_needle.begin(), lowered_needle.end(),
                 lowered_needle.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return haystack.find(lowered_needle) != std::wstring::npos;
}

bool IsKnownVirtualAdapter(const DXGI_ADAPTER_DESC1& desc) {
  const std::wstring name(desc.Description);
  return ContainsCaseInsensitive(name, L"sharing monitor") ||
         ContainsCaseInsensitive(name, L"virtual") ||
         ContainsCaseInsensitive(name, L"remote") ||
         ContainsCaseInsensitive(name, L"basic render") ||
         ContainsCaseInsensitive(name, L"microsoft basic");
}

bool HasProblematicZeroVramAdapter() {
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                  reinterpret_cast<void**>(&factory)))) {
    return false;
  }

  bool found_problematic_adapter = false;
  for (UINT index = 0;; ++index) {
    IDXGIAdapter1* adapter = nullptr;
    if (factory->EnumAdapters1(index, &adapter) == DXGI_ERROR_NOT_FOUND) {
      break;
    }

    DXGI_ADAPTER_DESC1 desc;
    if (SUCCEEDED(adapter->GetDesc1(&desc))) {
      const bool software =
          (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) == DXGI_ADAPTER_FLAG_SOFTWARE;
      // Flag ANY non-software adapter with 0 dedicated VRAM — these are
      // virtual/display-only adapters (Sharing Monitor, Remote Desktop, etc.)
      // that cannot render Flutter content.
      if (!software && desc.DedicatedVideoMemory == 0) {
        found_problematic_adapter = true;
      }
    }
    adapter->Release();
  }

  factory->Release();
  return found_problematic_adapter;
}

bool HasIntelArcOrLunarLakeAdapter() {
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                  reinterpret_cast<void**>(&factory)))) {
    return false;
  }

  bool found = false;
  for (UINT index = 0;; ++index) {
    IDXGIAdapter1* adapter = nullptr;
    if (factory->EnumAdapters1(index, &adapter) == DXGI_ERROR_NOT_FOUND) {
      break;
    }

    DXGI_ADAPTER_DESC1 desc;
    if (SUCCEEDED(adapter->GetDesc1(&desc))) {
      const std::wstring name(desc.Description);
      // Intel Arc discrete GPUs (e.g. "Intel(R) Arc(TM) A770M")
      if (ContainsCaseInsensitive(name, L"intel") &&
          ContainsCaseInsensitive(name, L"arc")) {
        found = true;
      }
      // Intel Lunar Lake integrated (e.g. "Intel(R) Arc(TM) 140V")
      if (ContainsCaseInsensitive(name, L"intel") &&
          ContainsCaseInsensitive(name, L"140v")) {
        found = true;
      }
    }
    adapter->Release();
  }

  factory->Release();
  return found;
}

}  // namespace

// Pre-flight check: verify critical DLLs are loadable before Flutter init.
// Provides a clear error message instead of a cryptic Windows DLL error dialog.
bool CheckCriticalDlls() {
  const wchar_t* criticalDlls[] = {
    L"flutter_windows.dll",
    L"flutter_secure_storage_windows_plugin.dll",
    L"isar.dll",
    L"window_manager_plugin.dll",
    nullptr
  };

  for (int i = 0; criticalDlls[i] != nullptr; i++) {
    HMODULE hMod = ::LoadLibraryW(criticalDlls[i]);
    if (!hMod) {
      wchar_t msg[512];
      swprintf_s(msg, 512,
        L"IntelliAttend cannot load %s.\n\n"
        L"The installation may be corrupted. Please reinstall the application.\n"
        L"If this persists, contact IntelliAttend support.",
        criticalDlls[i]);
      ::MessageBoxW(nullptr, msg,
        L"IntelliAttend SmartBoard - DLL Error",
        MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
      return false;
    }
    ::FreeLibrary(hMod);
  }
  return true;
}

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

  // Pre-flight: verify critical DLLs are loadable before Flutter init.
  // This catches ABI mismatches (stale flutter_windows.dll) early with a
  // clear error message instead of a cryptic Windows DLL load failure.
  if (!CheckCriticalDlls()) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  const bool native_crash_recovery = NativeCrashFlagExists();
  const bool force_high_performance_gpu =
      native_crash_recovery ||
      HasProblematicZeroVramAdapter() ||
      HasIntelArcOrLunarLakeAdapter() ||
      HasArgument(command_line_arguments, "--intelliattend-high-performance-gpu") ||
      EnvEquals(L"INTELLIATTEND_GPU_MODE", L"high_performance");
  const bool force_low_power_gpu =
      HasArgument(command_line_arguments, "--intelliattend-low-power-gpu") ||
      EnvEquals(L"INTELLIATTEND_GPU_MODE", L"low_power");

  if (force_high_performance_gpu) {
    project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
    if (!HasArgument(command_line_arguments, "--native-crash-recovery")) {
      command_line_arguments.push_back("--native-crash-recovery");
    }
  } else if (force_low_power_gpu) {
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
    WriteNativeCrashFlag(::GetLastError());
    ::MessageBoxW(
        nullptr,
        L"IntelliAttend could not start the Windows rendering engine. "
        L"The next launch will use GPU compatibility mode. If this repeats, "
        L"please update the Intel graphics driver and disable virtual display "
        L"adapters such as Sharing Monitor.",
        L"IntelliAttend SmartBoard - Display Compatibility",
        MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
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
