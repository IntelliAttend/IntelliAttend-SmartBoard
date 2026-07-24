#include "authenticode.h"
#include <windows.h>
#include <softpub.h>
#include <wintrust.h>

#pragma comment(lib, "wintrust.lib")

namespace ua {

bool VerifyAuthenticode(const std::wstring& filePath) {
  WINTRUST_FILE_INFO fileInfo = {};
  fileInfo.cbStruct       = sizeof(fileInfo);
  fileInfo.pcwszFilePath  = filePath.c_str();
  fileInfo.hFile          = nullptr;
  fileInfo.pgKnownSubject = nullptr;

  GUID actionId = WINTRUST_ACTION_GENERIC_VERIFY_V2;

  WINTRUST_DATA trustData = {};
  trustData.cbStruct            = sizeof(trustData);
  trustData.pPolicyCallbackData = nullptr;
  trustData.pSIPClientData      = nullptr;
  trustData.dwUIChoice          = WTD_UI_NONE;
  trustData.fdwRevocationChecks = WTD_REVOKE_NONE;
  trustData.dwUnionChoice       = WTD_CHOICE_FILE;
  trustData.dwStateAction       = WTD_STATEACTION_VERIFY;
  trustData.hWVTStateData       = nullptr;
  trustData.pwszURLReference    = nullptr;
  trustData.dwProvFlags         = WTD_SAFER_FLAG;
  trustData.dwUIContext          = 0;
  trustData.pFile               = &fileInfo;

  LONG status = WinVerifyTrust(
    static_cast<HWND>(INVALID_HANDLE_VALUE),
    &actionId,
    &trustData
  );

  // Clean up state data.
  trustData.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &actionId, &trustData);

  return status == ERROR_SUCCESS;
}

std::wstring GetSignerName(const std::wstring& filePath) {
  // Simplified: just check if signed. Full implementation would
  // extract the certificate subject name via CryptQueryObject.
  if (VerifyAuthenticode(filePath)) {
    return L"Verified Publisher";
  }
  return L"";
}

} // namespace ua
