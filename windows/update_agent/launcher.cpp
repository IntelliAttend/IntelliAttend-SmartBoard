#include "launcher.h"
#include "logger.h"
#include <vector>

namespace ua {

bool LaunchApp(const std::wstring& exePath, DWORD* outPid) {
  std::wstring cmdLine = L"\"" + exePath + L"\" --intelliattend-autostart";

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  std::vector<wchar_t> cmdBuf(cmdLine.begin(), cmdLine.end());
  cmdBuf.push_back(L'\0');

  BOOL created = CreateProcessW(
    nullptr,
    cmdBuf.data(),
    nullptr, nullptr,
    FALSE,
    CREATE_NO_WINDOW,
    nullptr, nullptr,
    &si, &pi
  );

  if (!created) return false;

  if (outPid) *outPid = pi.dwProcessId;

  // Brief wait to confirm process started (didn't crash immediately).
  DWORD waitResult = WaitForSingleObject(pi.hProcess, 100);

  // If process exited immediately, it crashed on start.
  if (waitResult == WAIT_OBJECT_0) {
    DWORD exitCode = 0;
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return false; // Process crashed.
  }

  // Process is running. Release handles (don't wait for exit).
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  return true;
}

} // namespace ua
