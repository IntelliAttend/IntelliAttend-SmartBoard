#pragma once

#include <string>

namespace ua {

// Verify that the installed exe exists and has the expected version.
// Returns true if verification passes.
bool VerifyInstalledVersion(const std::wstring& exePath, const std::wstring& expectedVersion);

// Get the version string from a file's VERSIONINFO resource.
// Returns empty string on failure.
std::wstring GetFileVersion(const std::wstring& exePath);

} // namespace ua
