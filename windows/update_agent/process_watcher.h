#pragma once

#include <windows.h>

namespace ua {

// Wait for a process to exit.
// Returns true if process exited within timeout, false on timeout.
bool WaitForProcessExit(DWORD pid, DWORD timeoutMs);

// Check if a process with the given PID is still running.
bool IsProcessRunning(DWORD pid);

// Terminate a process. Returns true on success.
bool TerminateProcessById(DWORD pid);

} // namespace ua
