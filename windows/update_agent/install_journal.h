#pragma once

#include <string>
#include <vector>

namespace ua {

// An install journal entry.
struct JournalEntry {
  std::wstring step;        // e.g. "download_complete", "install_start", "install_complete"
  std::wstring timestamp;   // ISO-8601 UTC
  std::wstring detail;      // Optional detail
  bool success = true;
};

// Append-only install journal. Records every step of the update process.
// If power dies mid-install, the journal tells you exactly where it stopped.
class InstallJournal {
public:
  // Initialize with a file path.
  static void Init(const std::wstring& path);

  // Record a step in the journal.
  static void Record(const std::wstring& step, bool success = true,
                     const std::wstring& detail = L"");

  // Read the journal entries from disk.
  static std::vector<JournalEntry> Read();

  // Delete the journal file.
  static void Clear();

private:
  static inline std::wstring s_path_;
};

} // namespace ua
