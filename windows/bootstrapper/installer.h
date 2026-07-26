#pragma once

#include <string>
#include <windows.h>

namespace bs {

// Find the MSI file next to the bootstrapper EXE.
// Returns empty string if not found.
std::wstring FindMsiNextToExe();

// Download the MSI from the server to the EXE's directory.
// Shows a progress dialog during download.
// Returns the local path to the downloaded MSI, or empty string on failure.
std::wstring DownloadMsi(HINSTANCE hInstance, const std::wstring& exeDir);

// Install the MSI using the Windows Installer API (in-process, no subprocess).
// Returns ERROR_SUCCESS (0) or ERROR_SUCCESS_REBOOT_REQUIRED (3010) on success.
UINT InstallMsi(const std::wstring& msiPath);

// Check if an MSI return code is considered successful.
bool IsMsiSuccess(UINT resultCode);

// Clean up any downloaded MSI files next to the bootstrapper EXE.
void CleanupDownloadedMsi();

} // namespace bs
