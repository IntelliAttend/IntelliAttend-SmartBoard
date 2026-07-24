#include "checksum.h"
#include <windows.h>
#include <wincrypt.h>
#include <sstream>
#include <iomanip>

#pragma comment(lib, "crypt32.lib")

namespace ua {

// Convert wide string to UTF-8 bytes.
static std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(),
                                  nullptr, 0, nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(),
                       &result[0], size, nullptr, nullptr);
  return result;
}

std::wstring ComputeChecksum(const std::wstring& payload) {
  std::string utf8 = WideToUtf8(payload);

  HCRYPTPROV hProv = 0;
  HCRYPTHASH hHash = 0;
  BYTE hash[32];
  DWORD hashLen = 32;

  if (!CryptAcquireContextW(&hProv, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT)) {
    return L"";
  }
  if (!CryptCreateHash(hProv, CALG_SHA_256, 0, 0, &hHash)) {
    CryptReleaseContext(hProv, 0);
    return L"";
  }
  if (!CryptHashData(hHash, (const BYTE*)utf8.c_str(), (DWORD)utf8.size(), 0)) {
    CryptDestroyHash(hHash);
    CryptReleaseContext(hProv, 0);
    return L"";
  }
  if (!CryptGetHashParam(hHash, HP_HASHVAL, hash, &hashLen, 0)) {
    CryptDestroyHash(hHash);
    CryptReleaseContext(hProv, 0);
    return L"";
  }

  CryptDestroyHash(hHash);
  CryptReleaseContext(hProv, 0);

  // Convert to hex string.
  std::wstringstream ss;
  ss << std::hex << std::setfill(L'0');
  for (DWORD i = 0; i < hashLen; i++) {
    ss << std::setw(2) << hash[i];
  }
  return ss.str();
}

bool VerifyChecksum(const std::map<std::wstring, std::wstring>& json) {
  auto it = json.find(L"checksum");
  if (it == json.end()) return false;

  std::wstring storedChecksum = it->second;

  // Rebuild JSON without checksum field.
  std::wstring payload = L"{";
  bool first = true;
  for (const auto& [key, value] : json) {
    if (key == L"checksum") continue;
    if (!first) payload += L",";
    first = false;

    // Check if value is a number (schema, app_pid, attempt).
    bool isNumber = false;
    if (key == L"schema" || key == L"app_pid" || key == L"attempt") {
      isNumber = true;
    }

    payload += L"\"" + key + L"\":";
    if (isNumber) {
      payload += value;
    } else {
      payload += L"\"" + value + L"\"";
    }
  }
  payload += L"}";

  std::wstring computed = ComputeChecksum(payload);
  return computed == storedChecksum;
}

} // namespace ua
