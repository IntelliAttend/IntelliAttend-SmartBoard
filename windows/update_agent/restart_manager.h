#pragma once

#include <string>
#include <vector>
#include <windows.h>

namespace ua {

// Process information from Restart Manager.
struct LockedProcess {
  DWORD pid;
  std::wstring name;
  std::wstring fullPath;
};

// Use the Windows Restart Manager to identify and coordinate
// with processes that lock files in the install directory.
class RestartManager {
public:
  // Register resources and get a session handle.
  static bool BeginSession(const std::wstring& directory);

  // Get list of processes locking files in the registered directory.
  static std::vector<LockedProcess> GetLockedProcesses();

  // Request locked processes to shut down gracefully.
  static bool ShutdownApplications();

  // End the Restart Manager session.
  static void EndSession();

private:
  static inline HANDLE s_session_ = nullptr;
  static inline std::wstring s_directory_;
};

} // namespace ua
