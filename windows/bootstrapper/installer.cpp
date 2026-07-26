#include "installer.h"
#include "common.h"
#include "dialog.h"
#include "logger.h"
#include <vector>
#include <shlwapi.h>
#include <winhttp.h>

#ifdef _MSC_VER
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "winhttp.lib")
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

std::wstring PrepareMsiForInstall(const std::wstring& msiPath) {
  // Create temp directory.
  wchar_t tempPath[MAX_PATH] = {};
  DWORD tempLen = GetTempPathW(MAX_PATH, tempPath);
  if (tempLen == 0 || tempLen >= MAX_PATH) return L"";

  std::wstring tempDir = std::wstring(tempPath) + L"IntelliAttend";
  CreateDirectoryW(tempDir.c_str(), nullptr);

  // Generate temp MSI filename with timestamp.
  SYSTEMTIME st;
  GetLocalTime(&st);
  wchar_t timestamp[32] = {};
  swprintf_s(timestamp, L"%04d%02d%02d_%02d%02d%02d",
    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

  std::wstring tempMsi = tempDir + L"\\setup_" + timestamp + L".msi";

  BS_LOG_INFO(L"PREPARE", (L"Copying MSI to temp: " + tempMsi).c_str());

  // Copy the MSI to temp.
  if (!CopyFileW(msiPath.c_str(), tempMsi.c_str(), FALSE)) {
    BS_LOG_ERROR(L"PREPARE", (L"Failed to copy MSI to temp, error: " + std::to_wstring(GetLastError())).c_str());
    return L"";
  }

  // Strip Mark-of-the-Web (Zone.Identifier alternate data stream).
  // This removes the "downloaded from internet" flag that causes Explorer
  // to block MSI execution.
  std::wstring zoneStream = tempMsi + L":Zone.Identifier";
  if (DeleteFileW(zoneStream.c_str())) {
    BS_LOG_INFO(L"PREPARE", L"Stripped Zone.Identifier from temp MSI");
  } else {
    // Zone.Identifier may not exist — that's fine.
    DWORD err = GetLastError();
    if (err != ERROR_FILE_NOT_FOUND) {
      BS_LOG_WARN(L"PREPARE", (L"Could not strip Zone.Identifier, error: " + std::to_wstring(err)).c_str());
    }
  }

  // Verify the copy is valid by checking file size.
  LARGE_INTEGER fileSize = {};
  HANDLE hFile = CreateFileW(tempMsi.c_str(), GENERIC_READ, FILE_SHARE_READ,
    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hFile != INVALID_HANDLE_VALUE) {
    GetFileSizeEx(hFile, &fileSize);
    CloseHandle(hFile);
  }

  if (fileSize.QuadPart == 0) {
    BS_LOG_ERROR(L"PREPARE", L"Temp MSI is empty, aborting");
    DeleteFileW(tempMsi.c_str());
    return L"";
  }

  BS_LOG_INFO(L"PREPARE", (L"MSI prepared: " + std::to_wstring(fileSize.QuadPart) + L" bytes").c_str());
  return tempMsi;
}

DWORD RunMsiExec(const std::wstring& msiPath, const std::wstring& logPath) {
  std::wstring cmdLine = L"msiexec.exe /i \"" + msiPath +
                         L"\" /passive /norestart /log \"" + logPath + L"\"";

  BS_LOG_INFO(L"INSTALL", (L"Running: " + cmdLine).c_str());

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  std::vector<wchar_t> cmdBuf(cmdLine.begin(), cmdLine.end());
  cmdBuf.push_back(L'\0');

  BOOL created = CreateProcessW(
    nullptr,
    cmdBuf.data(),
    nullptr, nullptr,
    FALSE,
    CREATE_NO_WINDOW,
    nullptr, nullptr,
    &si, &pi
  );

  if (!created) {
    BS_LOG_ERROR(L"INSTALL", (L"CreateProcessW failed, error: " + std::to_wstring(GetLastError())).c_str());
    return (DWORD)-1;
  }

  BS_LOG_INFO(L"INSTALL", L"msiexec started, waiting for completion...");

  DWORD waitResult = WaitForSingleObject(pi.hProcess, kMsiExecTimeoutMs);

  DWORD exitCode = 0;
  if (waitResult == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &exitCode);
  } else {
    BS_LOG_ERROR(L"INSTALL", L"msiexec timed out, terminating...");
    TerminateProcess(pi.hProcess, 1);
    WaitForSingleObject(pi.hProcess, 5000);
    GetExitCodeProcess(pi.hProcess, &exitCode);
  }

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  BS_LOG_INFO(L"INSTALL", (L"msiexec exit code: " + std::to_wstring(exitCode)).c_str());
  return exitCode;
}

bool IsMsiSuccess(DWORD exitCode) {
  return exitCode == 0 || exitCode == 3010;
}

void CleanupTempMsi(const std::wstring& tempMsiPath) {
  if (tempMsiPath.empty()) return;
  DeleteFileW(tempMsiPath.c_str());
  BS_LOG_INFO(L"CLEANUP", L"Removed temp MSI copy");
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
