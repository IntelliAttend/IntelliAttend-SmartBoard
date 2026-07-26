#include "installer.h"
#include "common.h"
#include "logger.h"
#include <vector>
#include <shlwapi.h>

#pragma comment(lib, "shlwapi.lib")

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

} // namespace bs
