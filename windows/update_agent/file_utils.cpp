#include "file_utils.h"

namespace ua {

bool FileExists(const std::wstring& path) {
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

uint64_t FileSize(const std::wstring& path) {
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
    return 0;
  }
  LARGE_INTEGER size;
  size.HighPart = data.nFileSizeHigh;
  size.LowPart = data.nFileSizeLow;
  return (uint64_t)size.QuadPart;
}

std::wstring DirectoryOf(const std::wstring& filePath) {
  size_t pos = filePath.find_last_of(L"\\/");
  if (pos == std::wstring::npos) return L".";
  return filePath.substr(0, pos);
}

bool DeleteFileSafe(const std::wstring& path) {
  if (!FileExists(path)) return true;
  return DeleteFileW(path.c_str()) != 0;
}

} // namespace ua
