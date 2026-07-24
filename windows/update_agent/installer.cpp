#include "installer.h"
#include "logger.h"
#include <sstream>

namespace ua {

DWORD RunMsiExec(const std::wstring& msiPath, const std::wstring& logPath) {
  // Build msiexec command line:
  // msiexec.exe /i "<msi>" /qn /norestart /log "<log>"
  std::wstring cmdLine = L"msiexec.exe /i \"" + msiPath +
                         L"\" /qn /norestart /log \"" + logPath + L"\"";

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  // Create the process with a mutable command line buffer.
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

  if (!created) {
    return (DWORD)-1;
  }

  UA_LOG_INFO(L"INSTALLING", L"msiexec started, waiting for completion...");

  // Wait for msiexec to finish.
  DWORD waitResult = WaitForSingleObject(pi.hProcess, 300000); // 5 min

  DWORD exitCode = 0;
  if (waitResult == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &exitCode);
  } else {
    // Timeout — kill msiexec.
    UA_LOG_ERROR(L"INSTALLING", L"msiexec timed out after 300s, terminating...");
    TerminateProcess(pi.hProcess, 1);
    WaitForSingleObject(pi.hProcess, 5000);
    GetExitCodeProcess(pi.hProcess, &exitCode);
  }

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return exitCode;
}

bool IsMsiSuccess(DWORD exitCode) {
  return exitCode == 0 || exitCode == 3010;
}

bool IsMsiRetryable(DWORD exitCode) {
  // Non-retryable: 1602 (cancelled), 1604 (suspended), 5 (access denied).
  if (exitCode == 1602 || exitCode == 1604 || exitCode == 5) return false;
  // Everything else is retryable.
  return !IsMsiSuccess(exitCode);
}

} // namespace ua
