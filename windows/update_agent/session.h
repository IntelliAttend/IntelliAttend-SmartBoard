#pragma once

#include <windows.h>

namespace ua {

// Check if the console session is active (user is logged in).
bool IsConsoleSessionActive();

// Get the active console session ID.
DWORD GetActiveSessionId();

} // namespace ua
