#include "session.h"
#include <wtsapi32.h>

#pragma comment(lib, "wtsapi32.lib")

namespace ua {

bool IsConsoleSessionActive() {
  DWORD sessionId = WTSGetActiveConsoleSessionId();
  return sessionId != 0xFFFFFFFF; // INVALID_SESSION_ID
}

DWORD GetActiveSessionId() {
  return WTSGetActiveConsoleSessionId();
}

} // namespace ua
