#include "logger.h"
#include <sstream>
#include <iomanip>

namespace bs {

Logger& Logger::Instance() {
  static Logger instance;
  return instance;
}

bool Logger::Init(const std::wstring& logPath) {
  hFile_ = CreateFileW(
    logPath.c_str(),
    GENERIC_WRITE,
    FILE_SHARE_READ,
    nullptr,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    nullptr
  );
  return hFile_ != INVALID_HANDLE_VALUE;
}

void Logger::Close() {
  if (hFile_ != INVALID_HANDLE_VALUE) {
    FlushFileBuffers(hFile_);
    CloseHandle(hFile_);
    hFile_ = INVALID_HANDLE_VALUE;
  }
}

std::wstring Logger::Timestamp() {
  SYSTEMTIME st;
  GetSystemTime(&st);

  std::wstringstream ss;
  ss << std::setfill(L'0')
     << std::setw(4) << st.wYear << L"-"
     << std::setw(2) << st.wMonth << L"-"
     << std::setw(2) << st.wDay << L"T"
     << std::setw(2) << st.wHour << L":"
     << std::setw(2) << st.wMinute << L":"
     << std::setw(2) << st.wSecond << L"."
     << std::setw(3) << st.wMilliseconds << L"Z";
  return ss.str();
}

void Logger::Log(const wchar_t* level, const wchar_t* state, const wchar_t* message) {
  if (hFile_ == INVALID_HANDLE_VALUE) return;

  std::wstring line;
  line += L"[" + Timestamp() + L"] ";
  line += L"[" + std::wstring(level) + L"]  ";
  line += std::wstring(state) + L": ";
  line += std::wstring(message) + L"\r\n";

  DWORD written = 0;
  WriteFile(hFile_, line.c_str(), (DWORD)(line.size() * sizeof(wchar_t)), &written, nullptr);
}

void Logger::Info(const wchar_t* state, const wchar_t* msg) {
  Log(L"INFO", state, msg);
}

void Logger::Warn(const wchar_t* state, const wchar_t* msg) {
  Log(L"WARN", state, msg);
}

void Logger::Error(const wchar_t* state, const wchar_t* msg) {
  Log(L"ERROR", state, msg);
}

} // namespace bs
