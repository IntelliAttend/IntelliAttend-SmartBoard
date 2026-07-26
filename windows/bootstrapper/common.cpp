#include "common.h"
#include <shlwapi.h>
#include <shellapi.h>

#ifdef _MSC_VER
#pragma comment(lib, "shlwapi.lib")
#endif

namespace bs {

std::wstring ExtractVersionFromExeName() {
  wchar_t exePath[MAX_PATH] = {};
  DWORD len = GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return L"";

  std::wstring fullPath(exePath, len);
  size_t lastSlash = fullPath.find_last_of(L'\\');
  std::wstring exeName = (lastSlash != std::wstring::npos)
    ? fullPath.substr(lastSlash + 1) : fullPath;

  // Expected pattern: intelliattend_smartboard-VERSION-x64-Setup.exe
  // Find the first '-' after the app name prefix.
  size_t dashPos = exeName.find(L'-');
  if (dashPos == std::wstring::npos) return L"";
  std::wstring afterFirstDash = exeName.substr(dashPos + 1);

  // Find the second '-' (before "x64").
  size_t secondDash = afterFirstDash.find(L'-');
  if (secondDash == std::wstring::npos) return L"";

  std::wstring version = afterFirstDash.substr(0, secondDash);
  return version.empty() ? L"" : version;
}

std::wstring BuildDownloadUrl(const std::wstring& version) {
  // https://github.com/IntelliAttend/IntelliAttend-SmartBoard/releases/download/v5.5.0.12/intelliattend_smartboard-5.5.0.12.msi
  return L"https://github.com/" + std::wstring(kGitHubRepo) +
         L"/releases/download/v" + version +
         L"/intelliattend_smartboard-" + version + L".msi";
}

bool HasSilentFlag() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return false;

  bool silent = false;
  for (int i = 1; i < argc; i++) {
    std::wstring arg(argv[i]);
    if (arg == L"/silent" || arg == L"/S" || arg == L"--silent" || arg == L"-s") {
      silent = true;
      break;
    }
  }
  LocalFree(argv);
  return silent;
}

} // namespace bs
