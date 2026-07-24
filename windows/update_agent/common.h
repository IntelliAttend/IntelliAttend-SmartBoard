#pragma once

#include <windows.h>
#include <string>
#include <cstdint>

namespace ua {

// Agent version (embedded in logs).
constexpr const wchar_t* kAgentVersion = L"1.0.0";

// Timeouts (milliseconds).
constexpr DWORD kWaitForAppExitMs     = 60000;   // 60s
constexpr DWORD kMsiExecTimeoutMs     = 300000;  // 5 min
constexpr DWORD kExePollTimeoutMs     = 10000;   // 10s
constexpr DWORD kLaunchWaitMs         = 5000;    // 5s
constexpr DWORD kCleanupTimeoutMs     = 5000;    // 5s
constexpr DWORD kAgentLifetimeMs      = 600000;  // 10 min

// Retry limits.
constexpr int kMsiMaxRetries = 3;
constexpr DWORD kMsiRetryDelays[] = { 5000, 10000, 10000 };

// MSI exit codes.
constexpr DWORD kMsiSuccess       = 0;
constexpr DWORD kMsiRebootRequired = 3010;

// Agent exit codes.
enum ExitCode : int {
  Success         = 0,
  AppExitTimeout  = 1,
  MsiInstallFail  = 2,
  VerifyFailed    = 3,
  RestartFailed   = 4,
  InvalidState    = 5,
};

// Agent states.
enum class State {
  Boot,
  Reading,
  WaitingAppExit,
  Installing,
  Verifying,
  Restarting,
  Cleanup,
  Done,
};

// Mutable fields from update_state.json.
struct UpdateState {
  int         schema        = 0;
  std::wstring owner;
  std::wstring msiPath;
  std::wstring targetVersion;
  std::wstring expectedSha256;
  int         appPid        = 0;
  std::wstring appExePath;
  std::wstring logPath;
  std::wstring state;
  std::wstring error;
  std::wstring createdAt;
  std::wstring completedAt;
  int         attempt       = 1;
  std::wstring checksum;
};

} // namespace ua
