#pragma once

#include <windows.h>
#include <string>

namespace ua {

// RAII wrapper for a named mutex. Ensures only one agent runs at a time.
class SingletonGuard {
public:
  // Try to acquire the global mutex. Returns false if another instance holds it.
  static bool Acquire(const std::wstring& name = L"Global\\IntelliAttend.UpdateAgent") {
    HANDLE hMutex = CreateMutexW(nullptr, TRUE, name.c_str());
    if (hMutex == nullptr) return false;

    DWORD err = GetLastError();
    if (err == ERROR_ALREADY_EXISTS) {
      CloseHandle(hMutex);
      return false;
    }

    Instance().hMutex_ = hMutex;
    return true;
  }

  // Release the mutex.
  static void Release() {
    auto& inst = Instance();
    if (inst.hMutex_ != nullptr) {
      ReleaseMutex(inst.hMutex_);
      CloseHandle(inst.hMutex_);
      inst.hMutex_ = nullptr;
    }
  }

private:
  SingletonGuard() = default;
  HANDLE hMutex_ = nullptr;

  static SingletonGuard& Instance() {
    static SingletonGuard inst;
    return inst;
  }
};

} // namespace ua
