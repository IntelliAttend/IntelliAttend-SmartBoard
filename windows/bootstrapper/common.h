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

enum ExitCode : int {
  Success            = 0,
  MsiNotFound        = 1,
  MsiCopyFailed      = 2,
  MsiInstallFailed   = 3,
  UserCancelled      = 4,
  LicenseNotAccepted = 5,
};

} // namespace bs
