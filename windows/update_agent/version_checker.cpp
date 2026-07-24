#include "version_checker.h"
#include "file_utils.h"
#include <windows.h>
#include <sstream>
#include <vector>

#pragma comment(lib, "version.lib")

namespace ua {

std::wstring GetFileVersion(const std::wstring& exePath) {
  if (!FileExists(exePath)) return L"";

  DWORD dummy;
  DWORD size = GetFileVersionInfoSizeW(exePath.c_str(), &dummy);
  if (size == 0) return L"";

  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(exePath.c_str(), 0, size, data.data())) {
    return L"";
  }

  VS_FIXEDFILEINFO* fileInfo = nullptr;
  UINT len = 0;
  if (!VerQueryValueW(data.data(), L"\\", (LPVOID*)&fileInfo, &len)) {
    return L"";
  }

  if (!fileInfo) return L"";

  DWORD major    = HIWORD(fileInfo->dwFileVersionMS);
  DWORD minor    = LOWORD(fileInfo->dwFileVersionMS);
  DWORD build    = HIWORD(fileInfo->dwFileVersionLS);
  DWORD revision = LOWORD(fileInfo->dwFileVersionLS);

  // Build version string like "5.6.0+12".
  std::wstringstream ss;
  ss << major << L"." << minor << L"." << build << L"+" << revision;
  return ss.str();
}

bool VerifyInstalledVersion(const std::wstring& exePath, const std::wstring& expectedVersion) {
  if (!FileExists(exePath)) return false;

  std::wstring actualVersion = GetFileVersion(exePath);
  if (actualVersion.empty()) return false;

  // Normalize: strip "v" prefix if present.
  if (!expectedVersion.empty() && expectedVersion[0] == L'v') {
    return actualVersion == expectedVersion.substr(1);
  }
  return actualVersion == expectedVersion;
}

} // namespace ua
