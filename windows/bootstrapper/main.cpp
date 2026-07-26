#include "common.h"
#include "logger.h"
#include "installer.h"
#include "dialog.h"
#include <shellapi.h>
#include <shlwapi.h>
#include <vector>

#pragma comment(lib, "shlwapi.lib")

namespace {

std::wstring GetExeDir() {
  wchar_t path[MAX_PATH] = {};
  DWORD len = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return L"";
  std::wstring fullPath(path, len);
  size_t pos = fullPath.find_last_of(L'\\');
  return (pos != std::wstring::npos) ? fullPath.substr(0, pos) : L"";
}

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

bool HasSilentFlag() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return false;

  bool silent = false;
  for (int i = 1; i < argc; i++) {
    std::wstring arg(argv[i]);
    // Case-insensitive comparison.
    if (arg == L"/silent" || arg == L"/S" || arg == L"--silent" || arg == L"-s") {
      silent = true;
      break;
    }
  }
  LocalFree(argv);
  return silent;
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR, int) {
  // Initialize logger.
  std::wstring logPath = GetLogPath();
  if (!logPath.empty()) {
    bs::Logger::Instance().Init(logPath);
  }

  BS_LOG_INFO(L"START", (L"Bootstrapper v" + std::wstring(bs::kBootstrapperVersion) + L" launched").c_str());

  // Find MSI next to this EXE.
  std::wstring msiPath = bs::FindMsiNextToExe();
  if (msiPath.empty()) {
    BS_LOG_ERROR(L"FIND_MSI", (L"No MSI found matching pattern: " + std::wstring(bs::kMsiPattern)).c_str());
    MessageBoxW(nullptr,
      L"No installer package found.\n\n"
      L"Please ensure the MSI file is in the same directory as this Setup program.",
      bs::kAppName, MB_OK | MB_ICONERROR);
    bs::Logger::Instance().Close();
    return (int)bs::ExitCode::MsiNotFound;
  }

  // Extract just the filename for display.
  std::wstring msiFileName = msiPath;
  size_t lastSlash = msiFileName.find_last_of(L'\\');
  if (lastSlash != std::wstring::npos) {
    msiFileName = msiFileName.substr(lastSlash + 1);
  }

  BS_LOG_INFO(L"FIND_MSI", (L"Found MSI: " + msiPath).c_str());

  bool silent = HasSilentFlag();
  bool accepted = true;

  if (!silent) {
    // Show license dialog.
    BS_LOG_INFO(L"DIALOG", L"Showing install dialog...");
    accepted = bs::ShowInstallDialog(hInstance, msiFileName);
  }

  if (!accepted) {
    BS_LOG_INFO(L"DIALOG", L"User declined license or cancelled");
    bs::Logger::Instance().Close();
    return (int)bs::ExitCode::UserCancelled;
  }

  BS_LOG_INFO(L"PREPARE", L"Preparing MSI for installation...");

  // Copy MSI to temp and strip Mark-of-the-Web.
  std::wstring tempMsi = bs::PrepareMsiForInstall(msiPath);
  if (tempMsi.empty()) {
    BS_LOG_ERROR(L"PREPARE", L"Failed to prepare MSI for installation");
    MessageBoxW(nullptr,
      L"Failed to prepare the installer package.\n\n"
      L"Please try running the MSI file directly.",
      bs::kAppName, MB_OK | MB_ICONERROR);
    bs::Logger::Instance().Close();
    return (int)bs::ExitCode::MsiCopyFailed;
  }

  // Run msiexec.
  BS_LOG_INFO(L"INSTALL", L"Starting installation...");
  DWORD exitCode = bs::RunMsiExec(tempMsi, logPath);

  // Clean up temp copy.
  bs::CleanupTempMsi(tempMsi);

  if (bs::IsMsiSuccess(exitCode)) {
    BS_LOG_INFO(L"INSTALL", (L"Installation successful, exit code: " + std::to_wstring(exitCode)).c_str());
  } else {
    BS_LOG_ERROR(L"INSTALL", (L"Installation failed, exit code: " + std::to_wstring(exitCode)).c_str());
  }

  // Show result dialog (unless silent).
  if (!silent) {
    bs::ShowResultDialog(exitCode);
  }

  bs::Logger::Instance().Close();
  return bs::IsMsiSuccess(exitCode) ? (int)bs::ExitCode::Success : (int)bs::ExitCode::MsiInstallFailed;
}
