#pragma once

#include <string>
#include <windows.h>

namespace bs {

class Logger {
public:
  static Logger& Instance();

  bool Init(const std::wstring& logPath);
  void Close();

  void Log(const wchar_t* level, const wchar_t* state, const wchar_t* message);
  void Info(const wchar_t* state, const wchar_t* msg);
  void Warn(const wchar_t* state, const wchar_t* msg);
  void Error(const wchar_t* state, const wchar_t* msg);

private:
  Logger() = default;
  HANDLE hFile_ = INVALID_HANDLE_VALUE;

  std::wstring Timestamp();
};

#define BS_LOG_INFO(state, msg)  bs::Logger::Instance().Info(state, msg)
#define BS_LOG_WARN(state, msg)  bs::Logger::Instance().Warn(state, msg)
#define BS_LOG_ERROR(state, msg) bs::Logger::Instance().Error(state, msg)

} // namespace bs
