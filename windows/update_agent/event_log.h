#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Write structured events to the Windows Event Log (Application source).
class EventLog {
public:
  // Register the event source (call once at startup).
  static void Register();

  // Unregister the event source.
  static void Unregister();

  // Write an informational event.
  static void Info(const wchar_t* message);

  // Write a warning event.
  static void Warn(const wchar_t* message);

  // Write an error event.
  static void Error(const wchar_t* message);

private:
  static inline HANDLE s_handle_ = nullptr;
};

} // namespace ua
