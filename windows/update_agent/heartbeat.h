#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Writes a heartbeat file periodically during install.
// If the heartbeat stops, the watchdog (app) knows the agent is hung.
class Heartbeat {
public:
  // Initialize with a file path. Creates the file.
  static void Init(const std::wstring& path);

  // Update the heartbeat timestamp. Call every few seconds during install.
  static void Pulse();

  // Delete the heartbeat file.
  static void Stop();

private:
  static inline std::wstring s_path_;
  static inline HANDLE s_file_ = INVALID_HANDLE_VALUE;
};

} // namespace ua
