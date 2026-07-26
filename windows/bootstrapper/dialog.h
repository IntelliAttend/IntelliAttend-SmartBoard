#pragma once

#include <string>
#include <windows.h>

namespace bs {

// Show the install dialog with license agreement.
// Returns true if user accepted and clicked Install, false if cancelled.
bool ShowInstallDialog(HINSTANCE hInstance, const std::wstring& msiFileName);

// Show a message box with the install result.
void ShowResultDialog(DWORD exitCode);

// Callback to update the download progress text.
void UpdateDownloadProgress(HWND hDlg, const std::wstring& text);

// Check if the user cancelled the download dialog.
bool IsDownloadCancelled();

// Show the download progress dialog (non-modal).
// hWndParent can be nullptr.
HWND ShowDownloadDialog(HINSTANCE hInstance, HWND hWndParent);

} // namespace bs
