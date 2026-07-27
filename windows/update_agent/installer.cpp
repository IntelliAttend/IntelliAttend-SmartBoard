#include "installer.h"
#include "logger.h"
#include <sstream>
#include <vector>

namespace ua {

DWORD RunSetupExe(const std::wstring& setupPath, const std::wstring& logPath) {
  // Build command line:
  // setup.exe /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="<log>"
  std::wstring cmdLine = L"\"" + setupPath +
                         L"\" /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG=\"" +
                         logPath + L"\"";

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

  UA_LOG_INFO(L"INSTALLING", L"setup.exe started, waiting for completion...");

  // Wait for setup to finish (10 min timeout — Inno Setup can be slow on HDD).
  DWORD waitResult = WaitForSingleObject(pi.hProcess, 600000);

  DWORD exitCode = 0;
  if (waitResult == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &exitCode);
  } else {
    // Timeout — kill the process.
    UA_LOG_ERROR(L"INSTALLING", L"setup.exe timed out after 600s, terminating...");
    TerminateProcess(pi.hProcess, 1);
    WaitForSingleObject(pi.hProcess, 5000);
    GetExitCodeProcess(pi.hProcess, &exitCode);
  }

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return exitCode;
}

bool IsInstallSuccess(DWORD exitCode) {
  // Inno Setup returns 0 on success.
  return exitCode == 0;
}

bool IsInstallRetryable(DWORD exitCode) {
  // Non-retryable: user cancelled (1 or 2), access denied (5).
  if (exitCode == 1 || exitCode == 2 || exitCode == 5) return false;
  return !IsInstallSuccess(exitCode);
}

} // namespace ua
