#include "process_watcher.h"

namespace ua {

bool WaitForProcessExit(DWORD pid, DWORD timeoutMs) {
  if (pid == 0) return true; // No PID to wait for.

  HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                                 FALSE, pid);
  if (!hProcess) return true; // Process doesn't exist — already exited.

  DWORD result = WaitForSingleObject(hProcess, timeoutMs);
  CloseHandle(hProcess);
  return result == WAIT_OBJECT_0;
}

bool IsProcessRunning(DWORD pid) {
  if (pid == 0) return false;

  HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!hProcess) return false;

  DWORD exitCode = 0;
  BOOL ok = GetExitCodeProcess(hProcess, &exitCode);
  CloseHandle(hProcess);

  if (!ok) return false;
  return exitCode == STILL_ACTIVE;
}

bool TerminateProcessById(DWORD pid) {
  if (pid == 0) return false;

  HANDLE hProcess = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
  if (!hProcess) return false;

  BOOL result = TerminateProcess(hProcess, 1);
  CloseHandle(hProcess);
  return result != 0;
}

} // namespace ua
