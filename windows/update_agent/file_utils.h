#pragma once

#include <string>
#include <windows.h>

namespace ua {

// Check if a file exists.
bool FileExists(const std::wstring& path);

// Get file size in bytes. Returns 0 on error.
uint64_t FileSize(const std::wstring& path);

// Get the directory containing a file path.
std::wstring DirectoryOf(const std::wstring& filePath);

// Delete a file. Returns true on success or if file doesn't exist.
bool DeleteFileSafe(const std::wstring& path);

} // namespace ua
