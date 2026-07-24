#pragma once

#include <string>
#include <windows.h>

namespace ua {

class Logger {
public:
  static Logger& Instance();

  // Initialize with log file path. Creates/opens the file.
  bool Init(const std::wstring& logPath);

  // Close the log file.
  void Close();

  // Log a message with level.
  void Log(const wchar_t* level, const wchar_t* state, const wchar_t* message);

  // Convenience methods.
  void Info(const wchar_t* state, const wchar_t* msg);
  void Warn(const wchar_t* state, const wchar_t* msg);
  void Error(const wchar_t* state, const wchar_t* msg);

private:
  Logger() = default;
  HANDLE hFile_ = INVALID_HANDLE_VALUE;

  // Get ISO-8601 UTC timestamp.
  std::wstring Timestamp();
};

// Macros for convenience.
#define UA_LOG_INFO(state, msg)  ua::Logger::Instance().Info(state, msg)
#define UA_LOG_WARN(state, msg)  ua::Logger::Instance().Warn(state, msg)
#define UA_LOG_ERROR(state, msg) ua::Logger::Instance().Error(state, msg)

} // namespace ua
