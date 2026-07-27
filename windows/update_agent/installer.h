#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Run the Inno Setup installer.
// Returns the exit code (0 = success).
DWORD RunSetupExe(const std::wstring& setupPath, const std::wstring& logPath);

// Check if an installer exit code is considered successful.
bool IsInstallSuccess(DWORD exitCode);

// Check if an installer exit code is retryable.
bool IsInstallRetryable(DWORD exitCode);

} // namespace ua
