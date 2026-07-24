#pragma once

#include <string>

namespace ua {

// Verify Authenticode signature of a file.
// Returns true if the signature is valid and trusted.
bool VerifyAuthenticode(const std::wstring& filePath);

// Get the signer name from a signed file. Returns empty string if unsigned.
std::wstring GetSignerName(const std::wstring& filePath);

} // namespace ua
