#pragma once

#include <string>
#include <windows.h>

namespace bs {

// Show the install dialog with license agreement.
// Returns true if user accepted and clicked Install, false if cancelled.
bool ShowInstallDialog(HINSTANCE hInstance, const std::wstring& msiFileName);

// Show a message box with the install result.
void ShowResultDialog(DWORD exitCode);

} // namespace bs
