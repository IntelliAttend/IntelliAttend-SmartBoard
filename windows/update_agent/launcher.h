#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Launch the application with the --intelliattend-autostart flag.
// Returns true if the process started successfully.
bool LaunchApp(const std::wstring& exePath, DWORD* outPid = nullptr);

} // namespace ua
