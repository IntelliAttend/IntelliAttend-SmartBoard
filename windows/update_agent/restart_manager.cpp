#include "restart_manager.h"
#include "logger.h"
#include <rstrtmgr.h>

#pragma comment(lib, "rstrtmgr.lib")

namespace ua {

bool RestartManager::BeginSession(const std::wstring& directory) {
  s_directory_ = directory;

  DWORD sessionHandle = 0;
  DWORD sessionId = 0;

  // Generate a unique session key.
  wchar_t sessionKey[CCH_RM_SESSION_KEY + 1];
  DWORD sessionKeyLen = sizeof(sessionKey) / sizeof(sessionKey[0]);
  if (GenerateRmUniqueSessionKey(sessionKey, &sessionKeyLen) != ERROR_SUCCESS) {
    return false;
  }

  DWORD result = RmStartSession(&sessionHandle, 0, sessionKey);
  if (result != ERROR_SUCCESS) return false;

  s_session_ = reinterpret_cast<HANDLE>(static_cast<uintptr_t>(sessionHandle));

  // Register the install directory as a resource.
  wchar_t pathBuf[MAX_PATH + 2];
  wcscpy_s(pathBuf, directory.c_str());
  pathBuf[directory.size() + 1] = L'\0'; // Double null-terminate.

  LPCWSTR files[] = { pathBuf };
  result = RmRegisterResources(
    sessionHandle,
    0, nullptr,  // No registration resources.
    1, files,    // One file (directory path — RM scans contents).
    0, nullptr   // No service stop.
  );

  if (result != ERROR_SUCCESS) {
    RmEndSession(sessionHandle);
    s_session_ = nullptr;
    return false;
  }

  return true;
}

std::vector<LockedProcess> RestartManager::GetLockedProcesses() {
  std::vector<LockedProcess> result;
  if (!s_session_) return result;

  DWORD sessionHandle = reinterpret_cast<DWORD>(s_session_);
  UINT processCount = 0;
  RM_PROCESS_INFO* processInfo = nullptr;

  DWORD queryResult = RmGetList(sessionHandle, &processCount, nullptr, nullptr);
  if (queryResult != ERROR_MORE_DATA && queryResult != ERROR_SUCCESS) {
    return result;
  }

  if (processCount == 0) return result;

  processInfo = new RM_PROCESS_INFO[processCount];
  DWORD bufSize = processCount;
  queryResult = RmGetList(sessionHandle, &processCount, &bufSize, processInfo);

  if (queryResult == ERROR_SUCCESS) {
    for (UINT i = 0; i < processCount; i++) {
      LockedProcess lp;
      lp.pid = processInfo[i].Process.dwProcessId;
      lp.name = processInfo[i].strAppName;
      // Convert app name to full path.
      wchar_t fullPath[MAX_PATH];
      if (GetModuleFileNameExW(
            nullptr,
            reinterpret_cast<HANDLE>(static_cast<uintptr_t>(processInfo[i].Process.dwProcessId)),
            fullPath, MAX_PATH)) {
        lp.fullPath = fullPath;
      }
      result.push_back(lp);
    }
  }

  delete[] processInfo;
  return result;
}

bool RestartManager::ShutdownApplications() {
  if (!s_session_) return false;

  DWORD sessionHandle = reinterpret_cast<DWORD>(s_session_);
  DWORD result = RmShutdown(sessionHandle, RmForceShutdown, nullptr);
  return result == ERROR_SUCCESS;
}

void RestartManager::EndSession() {
  if (s_session_) {
    DWORD sessionHandle = reinterpret_cast<DWORD>(s_session_);
    RmEndSession(sessionHandle);
    s_session_ = nullptr;
  }
}

} // namespace ua
