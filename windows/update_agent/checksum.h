#pragma once

#include <string>
#include <map>

namespace ua {

// Compute SHA-256 hex digest of a wide string (UTF-8 encoded).
std::wstring ComputeChecksum(const std::wstring& payload);

// Verify checksum field in parsed JSON matches computed hash.
bool VerifyChecksum(const std::map<std::wstring, std::wstring>& json);

} // namespace ua
