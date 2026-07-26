#pragma once

#include <windows.h>
#include <string>
#include <cstdint>

namespace bs {

constexpr const wchar_t* kBootstrapperVersion = L"1.0.0";
constexpr const wchar_t* kAppName = L"IntelliAttend SmartBoard";
constexpr const wchar_t* kMsiPattern = L"IntelliAttendSmartBoard-*.msi";

constexpr DWORD kMsiExecTimeoutMs = 300000;  // 5 min
constexpr DWORD kCopyTimeoutMs    = 30000;   // 30s

constexpr DWORD kMsiSuccess        = 0;
constexpr DWORD kMsiRebootRequired = 3010;

constexpr const wchar_t* kGitHubRepo = L"IntelliAttend/IntelliAttend-SmartBoard";

enum ExitCode : int {
  Success            = 0,
  MsiNotFound        = 1,
  MsiCopyFailed      = 2,
  MsiInstallFailed   = 3,
  UserCancelled      = 4,
  LicenseNotAccepted = 5,
  DownloadFailed     = 6,
};

// Extract the version string (e.g. "5.5.0.12") from the EXE filename.
// Returns empty string if the pattern doesn't match.
std::wstring ExtractVersionFromExeName();

// Build the GitHub release download URL for the MSI.
std::wstring BuildDownloadUrl(const std::wstring& version);

// Check if silent install mode was requested via command-line flags.
bool HasSilentFlag();

} // namespace bs
