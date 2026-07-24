#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Run msiexec to install the MSI.
// Returns the msiexec exit code (0 or 3010 = success).
DWORD RunMsiExec(const std::wstring& msiPath, const std::wstring& logPath);

// Check if an MSI exit code is considered successful.
bool IsMsiSuccess(DWORD exitCode);

// Check if an MSI exit code is retryable.
bool IsMsiRetryable(DWORD exitCode);

} // namespace ua
