#include "install_journal.h"
#include "file_utils.h"
#include <fstream>
#include <sstream>

namespace ua {

void InstallJournal::Init(const std::wstring& path) {
  s_path_ = path;
}

void InstallJournal::Record(const std::wstring& step, bool success,
                            const std::wstring& detail) {
  // Get UTC timestamp.
  SYSTEMTIME st;
  GetSystemTime(&st);
  wchar_t ts[64];
  swprintf_s(ts, L"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
             st.wYear, st.wMonth, st.wDay,
             st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);

  // Append to journal file.
  std::wofstream file(s_path_, std::ios::app);
  if (!file.is_open()) return;

  file << ts << L"|"
        << (success ? L"OK" : L"FAIL") << L"|"
        << step;
  if (!detail.empty()) {
    file << L"|" << detail;
  }
  file << L"\r\n";
  file.flush();
}

std::vector<JournalEntry> InstallJournal::Read() {
  std::vector<JournalEntry> entries;
  std::wifstream file(s_path_);
  if (!file.is_open()) return entries;

  std::wstring line;
  while (std::getline(file, line)) {
    if (line.empty()) continue;

    JournalEntry e;
    std::wistringstream ss(line);
    std::wstring token;

    // Parse pipe-delimited: timestamp|status|step|detail
    if (std::getline(ss, token, L'|')) e.timestamp = token;
    if (std::getline(ss, token, L'|')) e.success = (token == L"OK");
    if (std::getline(ss, token, L'|')) e.step = token;
    if (std::getline(ss, token, L'|')) e.detail = token;

    entries.push_back(e);
  }
  return entries;
}

void InstallJournal::Clear() {
  DeleteFileSafe(s_path_);
}

} // namespace ua
