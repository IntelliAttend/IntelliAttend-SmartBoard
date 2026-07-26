#include "installer.h"
#include "common.h"
#include "dialog.h"
#include "logger.h"
#include <vector>
#include <shlwapi.h>
#include <winhttp.h>
#include <msi.h>

#ifdef _MSC_VER
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "msi.lib")
#endif

namespace bs {

std::wstring FindMsiNextToExe() {
  // Get the directory containing this EXE.
  wchar_t exePath[MAX_PATH] = {};
  DWORD len = GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return L"";

  std::wstring exeDir(exePath, len);
  size_t lastSlash = exeDir.find_last_of(L'\\');
  if (lastSlash == std::wstring::npos) return L"";
  exeDir = exeDir.substr(0, lastSlash + 1);

  // Search for MSI files matching the pattern.
  WIN32_FIND_DATAW fd = {};
  std::wstring searchPath = exeDir + kMsiPattern;
  HANDLE hFind = FindFirstFileW(searchPath.c_str(), &fd);
  if (hFind == INVALID_HANDLE_VALUE) return L"";

  std::wstring result;
  do {
    // Skip directories.
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
    result = exeDir + fd.cFileName;
    break;  // Take the first match.
  } while (FindNextFileW(hFind, &fd));

  FindClose(hFind);
  return result;
}

UINT InstallMsi(const std::wstring& msiPath) {
  BS_LOG_INFO(L"INSTALL", (L"Installing MSI via Windows Installer API: " + msiPath).c_str());

  // Set UI level to none (fully silent).
  MsiSetInternalUI(INSTALLUILEVEL_NONE, nullptr);

  // Attempt install.
  UINT result = MsiInstallProductW(msiPath.c_str(), L"REBOOT=ReallySuppress");

  if (result == 1603) {
    // Product may already be installed. Try removing it first, then re-install.
    BS_LOG_INFO(L"INSTALL", L"Install failed (1603), trying remove+reinstall...");

    WCHAR productCode[39] = {};
    int idx = 0;
    while (MsiEnumProductsW(idx++, productCode) == ERROR_SUCCESS) {
      WCHAR name[256] = {};
      DWORD nameLen = 256;
      if (MsiGetProductInfoW(productCode, INSTALLPROPERTY_PRODUCTNAME, name, &nameLen) == ERROR_SUCCESS) {
        std::wstring productName(name, nameLen);
        if (productName.find(L"SmartBoard") != std::wstring::npos ||
            productName.find(L"IntelliAttend") != std::wstring::npos) {
          BS_LOG_INFO(L"INSTALL", (L"Found existing: " + productName + L" — uninstalling...").c_str());
          UINT removeResult = MsiConfigureProductW(productCode, INSTALLLEVEL_DEFAULT, INSTALLSTATE_ABSENT);
          BS_LOG_INFO(L"INSTALL", (L"MsiConfigureProduct returned: " + std::to_wstring(removeResult)).c_str());
          break;
        }
      }
      productCode[0] = L'\0';
    }

    // Give Windows Installer service time to finish cleanup after uninstall.
    Sleep(1000);

    // Verify the MSI file is still accessible before retrying.
    HANDLE hTest = CreateFileW(msiPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hTest == INVALID_HANDLE_VALUE) {
      BS_LOG_ERROR(L"INSTALL", (L"MSI file inaccessible before retry, error: " + std::to_wstring(GetLastError())).c_str());
      return 1603;
    }
    CloseHandle(hTest);

    // Retry install after uninstall.
    result = MsiInstallProductW(msiPath.c_str(), L"REBOOT=ReallySuppress");
    BS_LOG_INFO(L"INSTALL", (L"MsiInstallProduct (retry) returned: " + std::to_wstring(result)).c_str());
  }

  BS_LOG_INFO(L"INSTALL", (L"Final result: " + std::to_wstring(result)).c_str());
  return result;
}

bool IsMsiSuccess(UINT resultCode) {
  return resultCode == ERROR_SUCCESS || resultCode == ERROR_SUCCESS_REBOOT_REQUIRED;
}

void CleanupDownloadedMsi() {
  wchar_t exePath[MAX_PATH] = {};
  DWORD len = GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return;
  std::wstring fullPath(exePath, len);
  size_t lastSlash = fullPath.find_last_of(L'\\');
  std::wstring dir = (lastSlash != std::wstring::npos) ? fullPath.substr(0, lastSlash + 1) : L"";

  WIN32_FIND_DATAW fd = {};
  std::wstring search = dir + L"IntelliAttendSmartBoard-*.msi";
  HANDLE hFind = FindFirstFileW(search.c_str(), &fd);
  if (hFind != INVALID_HANDLE_VALUE) {
    do {
      if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
        std::wstring msiFile = dir + fd.cFileName;
        DeleteFileW(msiFile.c_str());
        BS_LOG_INFO(L"CLEANUP", (L"Removed downloaded MSI: " + msiFile).c_str());
      }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
  }
}

std::wstring DownloadMsi(HINSTANCE hInstance, const std::wstring& exeDir) {
  // Extract version from our own EXE name.
  std::wstring version = ExtractVersionFromExeName();
  if (version.empty()) {
    BS_LOG_ERROR(L"DOWNLOAD", L"Could not extract version from EXE name");
    return L"";
  }

  std::wstring url = BuildDownloadUrl(version);
  BS_LOG_INFO(L"DOWNLOAD", (L"Downloading from: " + url).c_str());

  // Parse the URL.
  URL_COMPONENTSW urlComp = {};
  urlComp.dwStructSize = sizeof(urlComp);
  urlComp.dwSchemeLength = 1;
  urlComp.dwHostNameLength = 1;
  urlComp.dwUrlPathLength = 1;
  urlComp.dwExtraInfoLength = 1;

  if (!WinHttpCrackUrl(url.c_str(), 0, 0, &urlComp)) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpCrackUrl failed, error: " + std::to_wstring(GetLastError())).c_str());
    return L"";
  }

  std::wstring hostName(urlComp.lpszHostName, urlComp.dwHostNameLength);
  std::wstring urlPath(urlComp.lpszUrlPath, urlComp.dwUrlPathLength);

  BS_LOG_INFO(L"DOWNLOAD", (L"Host: " + hostName + L" Path: " + urlPath).c_str());

  // Open session and connect.
  HINTERNET hSession = WinHttpOpen(
    L"IntelliAttendBootstrapper/1.0",
    WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_NO_PROXY_NAME,
    WINHTTP_NO_PROXY_BYPASS,
    0
  );
  if (!hSession) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpOpen failed, error: " + std::to_wstring(GetLastError())).c_str());
    return L"";
  }

  HINTERNET hConnect = WinHttpConnect(hSession, hostName.c_str(),
    urlComp.nPort, 0);
  if (!hConnect) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpConnect failed, error: " + std::to_wstring(GetLastError())).c_str());
    WinHttpCloseHandle(hSession);
    return L"";
  }

  DWORD flags = WINHTTP_FLAG_REFRESH;
  if (urlComp.nScheme == INTERNET_SCHEME_HTTPS) {
    flags |= WINHTTP_FLAG_SECURE;
  }

  HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", urlPath.c_str(),
    nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!hRequest) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpOpenRequest failed, error: " + std::to_wstring(GetLastError())).c_str());
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return L"";
  }

  // For HTTPS, set security flags to ignore certificate errors (self-signed cert on server).
  if (urlComp.nScheme == INTERNET_SCHEME_HTTPS) {
    DWORD securityFlags = SECURITY_FLAG_IGNORE_UNKNOWN_CA |
                          SECURITY_FLAG_IGNORE_CERT_DATE_INVALID |
                          SECURITY_FLAG_IGNORE_CERT_CN_INVALID |
                          SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &securityFlags, sizeof(securityFlags));
  }

  // Send the request.
  if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                          WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpSendRequest failed, error: " + std::to_wstring(GetLastError())).c_str());
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return L"";
  }

  if (!WinHttpReceiveResponse(hRequest, nullptr)) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpReceiveResponse failed, error: " + std::to_wstring(GetLastError())).c_str());
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return L"";
  }

  // Get content length.
  DWORD contentLength = 0;
  DWORD clSize = sizeof(contentLength);
  WinHttpQueryHeaders(hRequest,
    WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_HEADER_NAME_BY_INDEX,
    &contentLength, &clSize, WINHTTP_NO_HEADER_INDEX);
  BS_LOG_INFO(L"DOWNLOAD", (L"Content length: " + std::to_wstring(contentLength) + L" bytes").c_str());

  // Create the output file in the EXE directory.
  std::wstring outputPath = exeDir + L"IntelliAttendSmartBoard-" + version + L".msi";

  HANDLE hFile = CreateFileW(outputPath.c_str(), GENERIC_WRITE, 0,
    nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) {
    BS_LOG_ERROR(L"DOWNLOAD", (L"CreateFileW failed, error: " + std::to_wstring(GetLastError())).c_str());
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return L"";
  }

  // Show download dialog in a background thread.
  // We'll update progress via the dialog's progress text.
  HWND hDlg = nullptr;
  if (!bs::HasSilentFlag()) {
    hDlg = bs::ShowDownloadDialog(hInstance, nullptr);
  }

  // Read data in a loop.
  std::vector<BYTE> buffer(65536);
  DWORD totalBytesRead = 0;
  bool cancelled = false;

  for (;;) {
    // Check for user cancel.
    if (bs::IsDownloadCancelled()) {
      BS_LOG_INFO(L"DOWNLOAD", L"Download cancelled by user");
      cancelled = true;
      break;
    }

    DWORD bytesRead = 0;
    if (!WinHttpReadData(hRequest, buffer.data(), (DWORD)buffer.size(), &bytesRead)) {
      BS_LOG_ERROR(L"DOWNLOAD", (L"WinHttpReadData failed, error: " + std::to_wstring(GetLastError())).c_str());
      break;
    }

    if (bytesRead == 0) break;

    DWORD bytesWritten = 0;
    if (!WriteFile(hFile, buffer.data(), bytesRead, &bytesWritten, nullptr)) {
      BS_LOG_ERROR(L"DOWNLOAD", (L"WriteFile failed, error: " + std::to_wstring(GetLastError())).c_str());
      break;
    }

    totalBytesRead += bytesRead;

    // Update progress text directly (UI thread, same thread as download).
    if (hDlg) {
      int pct = (contentLength > 0) ? (int)((ULONGLONG)totalBytesRead * 100 / contentLength) : 0;
      std::wstring progress = L"Downloaded " + std::to_wstring(totalBytesRead / 1024) + L" KB";
      if (contentLength > 0) {
        progress += L" / " + std::to_wstring(contentLength / 1024) + L" KB (" + std::to_wstring(pct) + L"%)";
      }
      bs::UpdateDownloadProgress(hDlg, progress);
    }

    // Pump messages so the cancel button works.
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        cancelled = true;
        break;
      }
      if (!IsDialogMessageW(hDlg, &msg)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
      }
    }
    if (cancelled) break;
  }

  CloseHandle(hFile);
  WinHttpCloseHandle(hRequest);
  WinHttpCloseHandle(hConnect);
  WinHttpCloseHandle(hSession);

  if (hDlg && IsWindow(hDlg)) {
    DestroyWindow(hDlg);
  }

  if (cancelled) {
    BS_LOG_INFO(L"DOWNLOAD", L"Download cancelled by user");
    DeleteFileW(outputPath.c_str());
    return L"";
  }

  BS_LOG_INFO(L"DOWNLOAD", (L"Download complete: " + std::to_wstring(totalBytesRead) + L" bytes").c_str());

  if (totalBytesRead == 0) {
    BS_LOG_ERROR(L"DOWNLOAD", L"Download resulted in empty file");
    DeleteFileW(outputPath.c_str());
    return L"";
  }

  // Verify the downloaded file is not suspiciously small (less than 1MB).
  if (totalBytesRead < 1024 * 1024) {
    BS_LOG_ERROR(L"DOWNLOAD", L"Downloaded file too small, likely not a valid MSI");
    DeleteFileW(outputPath.c_str());
    return L"";
  }

  // Strip Mark-of-the-Web from the downloaded file.
  std::wstring zoneStream = outputPath + L":Zone.Identifier";
  if (DeleteFileW(zoneStream.c_str())) {
    BS_LOG_INFO(L"DOWNLOAD", L"Stripped Zone.Identifier from downloaded MSI");
  }

  BS_LOG_INFO(L"DOWNLOAD", (L"MSI saved to: " + outputPath).c_str());
  return outputPath;
}

} // namespace bs
