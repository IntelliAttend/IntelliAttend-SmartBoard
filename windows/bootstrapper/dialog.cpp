#include "dialog.h"
#include "common.h"
#include "installer.h"
#include "resource.h"
#include <string>

namespace bs {

static bool s_licenseAccepted = false;
static std::wstring s_msiFileName;

static const wchar_t* kLicenseText =
    L"INTELLIATTEND SMARTBOARD\r\n"
    L"END USER LICENSE AGREEMENT\r\n"
    L"\r\n"
    L"Last Updated: July 2026\r\n"
    L"\r\n"
    L"IMPORTANT - READ CAREFULLY\r\n"
    L"\r\n"
    L"This End User License Agreement (\"Agreement\") is a legal agreement between you "
    L"(\"User\" or \"Institution\") and IntelliAttend (\"Company\", \"we\", \"us\", or \"our\") "
    L"for the use of IntelliAttend SmartBoard software (\"Software\").\r\n"
    L"\r\n"
    L"By installing, copying, or using this Software, you agree to be bound by the terms of "
    L"this Agreement. If you do not agree, do not install or use the Software.\r\n"
    L"\r\n"
    L"1. GRANT OF LICENSE\r\n"
    L"IntelliAttend grants you a non-exclusive, non-transferable, limited license to install "
    L"and use the Software on a single device owned or controlled by your educational "
    L"institution, solely for internal educational attendance tracking purposes.\r\n"
    L"\r\n"
    L"2. DESCRIPTION OF RIGHTS AND LIMITATIONS\r\n"
    L"  a. The Software is licensed, not sold, to you.\r\n"
    L"  b. You may not reverse engineer, decompile, or disassemble the Software.\r\n"
    L"  c. You may not rent, lease, or lend the Software to third parties.\r\n"
    L"  d. You may not use the Software for any unlawful purpose.\r\n"
    L"  e. You may not modify, adapt, or create derivative works based on the Software.\r\n"
    L"\r\n"
    L"3. DATA COLLECTION AND PRIVACY\r\n"
    L"  a. The Software collects attendance data including student identifiers, timestamps, "
    L"and device information.\r\n"
    L"  b. All data is transmitted to and stored on IntelliAttend servers in accordance with "
    L"our Privacy Policy.\r\n"
    L"  c. By using this Software, you consent to the collection and processing of data as "
    L"described in the Privacy Policy.\r\n"
    L"  d. Institution administrators are responsible for obtaining necessary consents from "
    L"students and staff.\r\n"
    L"\r\n"
    L"4. INTELLECTUAL PROPERTY\r\n"
    L"The Software and all copies thereof are proprietary to IntelliAttend and its licensors. "
    L"All title and intellectual property rights in and to the Software are owned by "
    L"IntelliAttend.\r\n"
    L"\r\n"
    L"5. DEVICE REQUIREMENTS\r\n"
    L"The Software requires a 64-bit Windows operating system, an active internet connection, "
    L"and compatible hardware.\r\n"
    L"\r\n"
    L"6. AUTOMATIC UPDATES\r\n"
    L"The Software may automatically check for and install updates. Updates may be downloaded "
    L"and installed without additional notice to you.\r\n"
    L"\r\n"
    L"7. LIMITATION OF LIABILITY\r\n"
    L"IN NO EVENT SHALL INTELLIATTEND BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, "
    L"CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF OR RELATED TO THE USE OF THE "
    L"SOFTWARE, EVEN IF INTELLIATTEND HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.\r\n"
    L"\r\n"
    L"8. DISCLAIMER OF WARRANTIES\r\n"
    L"THE SOFTWARE IS PROVIDED \"AS IS\" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR "
    L"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A "
    L"PARTICULAR PURPOSE, AND NON-INFRINGEMENT.\r\n"
    L"\r\n"
    L"9. TERMINATION\r\n"
    L"This Agreement is effective until terminated. IntelliAttend may terminate this Agreement "
    L"at any time if you fail to comply with any term of this Agreement. Upon termination, you "
    L"must destroy all copies of the Software.\r\n"
    L"\r\n"
    L"10. GOVERNING LAW\r\n"
    L"This Agreement shall be governed by and construed in accordance with the laws of the "
    L"jurisdiction in which IntelliAttend operates.\r\n"
    L"\r\n"
    L"11. CONTACT\r\n"
    L"For questions about this Agreement, contact: support@intelliattend.app\r\n";

static INT_PTR CALLBACK InstallDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM /*lParam*/) {
  switch (msg) {
    case WM_INITDIALOG: {
      // Set title text.
      HWND hTitle = GetDlgItem(hDlg, IDC_TITLE_TEXT);
      if (hTitle) {
        std::wstring title = std::wstring(kAppName) + L" Installer";
        SetWindowTextW(hTitle, title.c_str());
      }

      // Load license text.
      HWND hLicense = GetDlgItem(hDlg, IDC_LICENSE_TEXT);
      if (hLicense) {
        SetWindowTextW(hLicense, kLicenseText);
        // Scroll to top.
        SendMessageW(hLicense, EM_SETSEL, 0, 0);
        SendMessageW(hLicense, EM_SCROLLCARET, 0, 0);
      }

      // Set default radio to decline.
      CheckRadioButton(hDlg, IDC_ACCEPT_RADIO, IDC_DECLINE_RADIO, IDC_DECLINE_RADIO);

      // Show MSI filename in status.
      HWND hStatus = GetDlgItem(hDlg, IDC_STATUS_TEXT);
      if (hStatus && !s_msiFileName.empty()) {
        SetWindowTextW(hStatus, (L"MSI: " + s_msiFileName).c_str());
      }

      // Center the dialog on screen.
      RECT rcDlg, rcScreen;
      GetWindowRect(hDlg, &rcDlg);
      GetWindowRect(GetDesktopWindow(), &rcScreen);
      int x = (rcScreen.right - rcScreen.left - (rcDlg.right - rcDlg.left)) / 2;
      int y = (rcScreen.bottom - rcScreen.top - (rcDlg.bottom - rcDlg.top)) / 2;
      SetWindowPos(hDlg, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);

      return TRUE;
    }

    case WM_COMMAND: {
      WORD controlId = LOWORD(wParam);

      switch (controlId) {
        case IDC_ACCEPT_RADIO:
        case IDC_DECLINE_RADIO: {
          // Enable/disable Install button based on radio selection.
          BOOL accepted = IsDlgButtonChecked(hDlg, IDC_ACCEPT_RADIO) == BST_CHECKED;
          EnableWindow(GetDlgItem(hDlg, IDC_INSTALL_BTN), accepted);
          break;
        }

        case IDC_INSTALL_BTN: {
          if (IsDlgButtonChecked(hDlg, IDC_ACCEPT_RADIO) == BST_CHECKED) {
            s_licenseAccepted = true;
            EndDialog(hDlg, IDOK);
          }
          break;
        }

        case IDC_CANCEL_BTN:
          s_licenseAccepted = false;
          EndDialog(hDlg, IDCANCEL);
          break;

        case IDCLOSE:
        case WM_CLOSE:
          s_licenseAccepted = false;
          EndDialog(hDlg, IDCANCEL);
          break;
      }
      return TRUE;
    }

    default:
      return FALSE;
  }
}

bool ShowInstallDialog(HINSTANCE hInstance, const std::wstring& msiFileName) {
  s_msiFileName = msiFileName;
  s_licenseAccepted = false;

  INT_PTR result = DialogBoxParamW(
    hInstance,
    MAKEINTRESOURCEW(IDD_INSTALL_DIALOG),
    nullptr,
    InstallDlgProc,
    0
  );

  return s_licenseAccepted && result == IDOK;
}

void ShowResultDialog(DWORD exitCode) {
  std::wstring title = std::wstring(kAppName) + L" Setup";
  std::wstring message;
  UINT flags;

  if (IsMsiSuccess(exitCode)) {
    message = kAppName;
    message += L" has been installed successfully.";
    if (exitCode == 3010) {
      message += L"\r\n\r\nA system restart is required to complete the installation.";
    }
    flags = MB_OK | MB_ICONINFORMATION;
  } else {
    message = L"Installation failed with exit code: ";
    message += std::to_wstring(exitCode);
    message += L"\r\n\r\nPlease check the install log for details, or try running the MSI directly.";
    flags = MB_OK | MB_ICONERROR;
  }

  MessageBoxW(nullptr, message.c_str(), title.c_str(), flags);
}

// ── Download dialog ────────────────────────────────────────────────────────────

#define WM_DOWNLOAD_PROGRESS (WM_USER + 1)

static HWND s_hDownloadDlg = nullptr;
static bool s_downloadCancelled = false;

bool IsDownloadCancelled() {
  return s_downloadCancelled;
}

void UpdateDownloadProgress(HWND hDlg, const std::wstring& text) {
  if (!hDlg) return;
  HWND hStatus = GetDlgItem(hDlg, IDC_PROGRESS_TEXT);
  if (hStatus) SetWindowTextW(hStatus, text.c_str());
}

static INT_PTR CALLBACK DownloadDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM /*lParam*/) {
  switch (msg) {
    case WM_INITDIALOG: {
      s_hDownloadDlg = hDlg;
      s_downloadCancelled = false;
      HWND hStatus = GetDlgItem(hDlg, IDC_PROGRESS_TEXT);
      if (hStatus) SetWindowTextW(hStatus, L"Connecting to server...");

      // Center on screen.
      RECT rcDlg, rcScreen;
      GetWindowRect(hDlg, &rcDlg);
      GetWindowRect(GetDesktopWindow(), &rcScreen);
      int x = (rcScreen.right - rcScreen.left - (rcDlg.right - rcDlg.left)) / 2;
      int y = (rcScreen.bottom - rcScreen.top - (rcDlg.bottom - rcDlg.top)) / 2;
      SetWindowPos(hDlg, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
      return TRUE;
    }

    case WM_COMMAND:
      if (LOWORD(wParam) == IDC_CANCEL_BTN) {
        s_downloadCancelled = true;
        DestroyWindow(hDlg);
      }
      return TRUE;

    case WM_CLOSE:
      s_downloadCancelled = true;
      DestroyWindow(hDlg);
      return TRUE;

    default:
      return FALSE;
  }
}

HWND ShowDownloadDialog(HINSTANCE hInstance, HWND hWndParent) {
  HWND hDlg = CreateDialogParamW(
    hInstance,
    MAKEINTRESOURCEW(IDD_DOWNLOAD_DIALOG),
    hWndParent,
    DownloadDlgProc,
    0
  );
  return hDlg;
}

} // namespace bs
