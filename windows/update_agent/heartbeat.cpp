#include "heartbeat.h"
#include "file_utils.h"

namespace ua {

void Heartbeat::Init(const std::wstring& path) {
  s_path_ = path;

  // Create/truncate the heartbeat file.
  s_file_ = CreateFileW(
    path.c_str(),
    GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_DELETE,
    nullptr,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    nullptr
  );
}

void Heartbeat::Pulse() {
  if (s_file_ == INVALID_HANDLE_VALUE) return;

  // Write current timestamp.
  SYSTEMTIME st;
  GetSystemTime(&st);
  wchar_t buf[64];
  swprintf_s(buf, L"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
             st.wYear, st.wMonth, st.wDay,
             st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);

  DWORD written = 0;
  SetFilePointer(s_file_, 0, nullptr, FILE_BEGIN);
  WriteFile(s_file_, buf, (DWORD)(wcslen(buf) * sizeof(wchar_t)), &written, nullptr);
  SetEndOfFile(s_file_);
  FlushFileBuffers(s_file_);
}

void Heartbeat::Stop() {
  if (s_file_ != INVALID_HANDLE_VALUE) {
    CloseHandle(s_file_);
    s_file_ = INVALID_HANDLE_VALUE;
  }
  DeleteFileSafe(s_path_);
}

} // namespace ua
