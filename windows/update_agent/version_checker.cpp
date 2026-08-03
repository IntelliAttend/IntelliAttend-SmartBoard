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

  // Build version string like "5.6.0.23" — must match the manifest's
  // minimumVersion format (4-part dot notation). The old format used
  // "5.6.0+12" which failed post-install verification against the manifest.
  std::wstringstream ss;
  ss << major << L"." << minor << L"." << build << L"." << revision;
  return ss.str();
}

bool VerifyInstalledVersion(const std::wstring& exePath, const std::wstring& expectedVersion) {
  if (!FileExists(exePath)) return false;

  std::wstring actualVersion = GetFileVersion(exePath);
  if (actualVersion.empty()) return false;

  // Normalize: strip "v" prefix if present.
  std::wstring normalized = expectedVersion;
  if (!normalized.empty() && normalized[0] == L'v') {
    normalized = normalized.substr(1);
  }

  // Direct match (e.g. "5.5.0.23" == "5.5.0.23").
  if (actualVersion == normalized) return true;

  // Fallback: compare major.minor.patch only (ignore revision/build differences)
  // so that old-format comparisons still work during transition.
  auto dotCount = [](const std::wstring& s) {
    int count = 0;
    for (auto c : s) if (c == L'.') count++;
    return count;
  };

  auto extractMajorMinorPatch = [](const std::wstring& s) -> std::wstring {
    // Take first 3 dot-separated segments.
    int dots = 0;
    for (size_t i = 0; i < s.size(); i++) {
      if (s[i] == L'.') {
        dots++;
        if (dots >= 3) return s.substr(0, i);
      }
    }
    return s;
  };

  if (dotCount(actualVersion) >= 3 && dotCount(normalized) >= 3) {
    return extractMajorMinorPatch(actualVersion) == extractMajorMinorPatch(normalized);
  }

  return false;
}

} // namespace ua
