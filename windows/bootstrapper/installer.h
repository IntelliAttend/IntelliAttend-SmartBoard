#pragma once

#include <string>
#include <windows.h>

namespace bs {

// Find the MSI file next to the bootstrapper EXE.
// Returns empty string if not found.
std::wstring FindMsiNextToExe();

// Copy the MSI to a temp directory and strip Mark-of-the-Web.
// Returns the temp MSI path, or empty string on failure.
std::wstring PrepareMsiForInstall(const std::wstring& msiPath);

// Run msiexec to install the MSI.
// Returns the msiexec exit code (0 or 3010 = success).
DWORD RunMsiExec(const std::wstring& msiPath, const std::wstring& logPath);

// Check if an MSI exit code is considered successful.
bool IsMsiSuccess(DWORD exitCode);

// Clean up the temp MSI copy.
void CleanupTempMsi(const std::wstring& tempMsiPath);

} // namespace bs
