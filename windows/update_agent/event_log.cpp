#include "event_log.h"
#include <windows.h>

namespace ua {

void EventLog::Register() {
  // Register "IntelliAttend Update" as an event source in the Application log.
  HKEY hKey = nullptr;
  if (RegCreateKeyExW(
        HKEY_LOCAL_MACHINE,
        L"SYSTEM\\CurrentControlSet\\Services\\EventLog\\Application\\IntelliAttend Update",
        0, nullptr, 0, KEY_SET_VALUE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
    // Point to the agent executable as the event message file.
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(nullptr, exePath, MAX_PATH);
    RegSetValueExW(hKey, L"EventMessageFile", 0, REG_SZ,
                   (BYTE*)exePath, (DWORD)((wcslen(exePath) + 1) * sizeof(wchar_t)));
    DWORD types = EVENTLOG_ERROR_TYPE | EVENTLOG_WARNING_TYPE | EVENTLOG_INFORMATION_TYPE;
    RegSetValueExW(hKey, L"TypesSupported", 0, REG_DWORD,
                   (BYTE*)&types, sizeof(types));
    RegCloseKey(hKey);
  }

  s_handle_ = RegisterEventSourceW(nullptr, L"IntelliAttend Update");
}

void EventLog::Unregister() {
  if (s_handle_) {
    DeregisterEventSource(s_handle_);
    s_handle_ = nullptr;
  }
}

static void ReportEvent(HANDLE handle, WORD type, const wchar_t* message) {
  if (!handle) return;
  const wchar_t* strings[1] = { message };
  ::ReportEventW(handle, type, 0, 0, nullptr, 1, 0, strings, nullptr);
}

void EventLog::Info(const wchar_t* message) {
  ReportEvent(s_handle_, EVENTLOG_INFORMATION_TYPE, message);
}

void EventLog::Warn(const wchar_t* message) {
  ReportEvent(s_handle_, EVENTLOG_WARNING_TYPE, message);
}

void EventLog::Error(const wchar_t* message) {
  ReportEvent(s_handle_, EVENTLOG_ERROR_TYPE, message);
}

} // namespace ua
