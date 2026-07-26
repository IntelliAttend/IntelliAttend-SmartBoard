#include "common.h"
#include "logger.h"
#include "installer.h"
#include "dialog.h"
#include <shellapi.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <vector>

#ifdef _MSC_VER
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")
#endif

namespace {

std::wstring GetLogPath() {
  wchar_t tempPath[MAX_PATH] = {};
  DWORD tempLen = GetTempPathW(MAX_PATH, tempPath);
  if (tempLen == 0 || tempLen >= MAX_PATH) return L"";

  // Create directory hierarchy: Temp\IntelliAttend\Logs
  std::wstring baseDir = std::wstring(tempPath) + L"IntelliAttend";
  CreateDirectoryW(baseDir.c_str(), nullptr);
  std::wstring logDir = baseDir + L"\\Logs";
  CreateDirectoryW(logDir.c_str(), nullptr);

  SYSTEMTIME st;
  GetLocalTime(&st);
  wchar_t filename[64] = {};
  swprintf_s(filename, L"bootstrap_%04d%02d%02d_%02d%02d%02d.log",
    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

  return logDir + L"\\" + filename;
}

std::wstring GetExeDir() {
  wchar_t exePath[MAX_PATH] = {};
  DWORD len = GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return L"";
  std::wstring fullPath(exePath, len);
  size_t lastSlash = fullPath.find_last_of(L'\\');
  return (lastSlash != std::wstring::npos) ? fullPath.substr(0, lastSlash + 1) : L"";
}

void LaunchApp() {
  wchar_t localAppData[MAX_PATH] = {};
  if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData) != S_OK) return;

  std::wstring appPath = std::wstring(localAppData) + L"\\IntelliAttendSmartBoard\\App\\intelliattend_smartboard.exe";
  if (GetFileAttributesW(appPath.c_str()) == INVALID_FILE_ATTRIBUTES) return;

  ShellExecuteW(nullptr, L"open", appPath.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR, int) {
  // Initialize logger.
  std::wstring logPath = GetLogPath();
  if (!logPath.empty()) {
    bs::Logger::Instance().Init(logPath);
  }

  BS_LOG_INFO(L"START", (L"Bootstrapper v" + std::wstring(bs::kBootstrapperVersion) + L" launched").c_str());

  // Find MSI next to this EXE, or download it.
  std::wstring msiPath = bs::FindMsiNextToExe();
  if (msiPath.empty()) {
    BS_LOG_INFO(L"FIND_MSI", L"No MSI found locally, attempting download...");
    std::wstring exeDir = GetExeDir();
    msiPath = bs::DownloadMsi(hInstance, exeDir);
    if (msiPath.empty()) {
      BS_LOG_ERROR(L"DOWNLOAD", L"Failed to download MSI installer package");
      MessageBoxW(nullptr,
        L"Failed to download the installer. Please check your internet connection and try again.",
        bs::kAppName, MB_OK | MB_ICONERROR);
      bs::Logger::Instance().Close();
      return (int)bs::ExitCode::DownloadFailed;
    }
    BS_LOG_INFO(L"DOWNLOAD", (L"MSI downloaded to: " + msiPath).c_str());
  } else {
    BS_LOG_INFO(L"FIND_MSI", (L"Found MSI: " + msiPath).c_str());
  }

  bool silent = bs::HasSilentFlag();
  bool accepted = true;

  if (!silent) {
    // Show license dialog.
    std::wstring msiFileName = msiPath;
    size_t lastSlash = msiFileName.find_last_of(L'\\');
    if (lastSlash != std::wstring::npos) msiFileName = msiFileName.substr(lastSlash + 1);
    BS_LOG_INFO(L"DIALOG", L"Showing install dialog...");
    accepted = bs::ShowInstallDialog(hInstance, msiFileName);
  }

  if (!accepted) {
    BS_LOG_INFO(L"DIALOG", L"User declined license or cancelled");
    bs::CleanupDownloadedMsi();
    bs::Logger::Instance().Close();
    return (int)bs::ExitCode::UserCancelled;
  }

  // Install via Windows Installer API (in-process, no subprocess).
  // Zone.Identifier was already stripped during download.
  BS_LOG_INFO(L"INSTALL", L"Starting installation...");
  UINT installResult = bs::InstallMsi(msiPath);

  if (bs::IsMsiSuccess(installResult)) {
    BS_LOG_INFO(L"INSTALL", (L"Installation successful, result: " + std::to_wstring(installResult)).c_str());

    // Clean up any downloaded MSI in the EXE directory.
    bs::CleanupDownloadedMsi();

    // Launch the installed application.
    BS_LOG_INFO(L"LAUNCH", L"Launching application...");
    LaunchApp();
  } else {
    BS_LOG_ERROR(L"INSTALL", (L"Installation failed, result: " + std::to_wstring(installResult)).c_str());
    if (!silent) {
      std::wstring title = std::wstring(bs::kAppName) + L" Setup";
      std::wstring msg = L"Installation failed (error " + std::to_wstring(installResult) + L").\nPlease try again.";
      MessageBoxW(nullptr, msg.c_str(), title.c_str(), MB_OK | MB_ICONERROR);
    }
  }

  bs::Logger::Instance().Close();
  return bs::IsMsiSuccess(installResult) ? (int)bs::ExitCode::Success : (int)bs::ExitCode::MsiInstallFailed;
}
