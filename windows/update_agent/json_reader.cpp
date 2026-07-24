#include "json_reader.h"
#include "checksum.h"
#include <fstream>
#include <sstream>
#include <algorithm>

namespace ua {

// Trim whitespace from both ends.
static std::wstring Trim(const std::wstring& s) {
  size_t start = s.find_first_not_of(L" \t\r\n");
  if (start == std::wstring::npos) return L"";
  size_t end = s.find_last_not_of(L" \t\r\n");
  return s.substr(start, end - start + 1);
}

// Parse a flat JSON object: { "key": "value", "key2": 123 }
// Returns map of string keys to string values (integers converted to string).
static std::map<std::wstring, std::wstring> ParseFlatJson(const std::wstring& json) {
  std::map<std::wstring, std::wstring> result;

  // Find the opening brace.
  size_t brace = json.find(L'{');
  if (brace == std::wstring::npos) return result;

  size_t pos = brace + 1;
  while (pos < json.size()) {
    // Skip whitespace.
    while (pos < json.size() && (json[pos] == L' ' || json[pos] == L'\t' ||
           json[pos] == L'\r' || json[pos] == L'\n')) pos++;
    if (pos >= json.size() || json[pos] == L'}') break;

    // Expect a quoted key.
    if (json[pos] != L'"') break;
    pos++; // skip opening quote
    size_t keyEnd = json.find(L'"', pos);
    if (keyEnd == std::wstring::npos) break;
    std::wstring key = json.substr(pos, keyEnd - pos);
    pos = keyEnd + 1;

    // Skip colon and whitespace.
    while (pos < json.size() && (json[pos] == L':' || json[pos] == L' ' ||
           json[pos] == L'\t')) pos++;
    if (pos >= json.size()) break;

    // Parse value (string, number, null, bool).
    std::wstring value;
    if (json[pos] == L'"') {
      // String value.
      pos++; // skip opening quote
      size_t valEnd = pos;
      while (valEnd < json.size()) {
        if (json[valEnd] == L'\\' && valEnd + 1 < json.size()) {
          valEnd += 2; // skip escaped char
          continue;
        }
        if (json[valEnd] == L'"') break;
        valEnd++;
      }
      value = json.substr(pos, valEnd - pos);
      pos = valEnd + 1; // skip closing quote
    } else {
      // Non-string value (number, null, bool).
      size_t valStart = pos;
      while (pos < json.size() && json[pos] != L',' && json[pos] != L'}' &&
             json[pos] != L'\n' && json[pos] != L'\r') pos++;
      value = Trim(json.substr(valStart, pos - valStart));
    }

    result[key] = value;

    // Skip comma.
    while (pos < json.size() && (json[pos] == L' ' || json[pos] == L'\t')) pos++;
    if (pos < json.size() && json[pos] == L',') pos++;
  }

  return result;
}

std::map<std::wstring, std::wstring> ReadJson(const std::wstring& path) {
  std::wifstream file(path);
  if (!file.is_open()) return {};

  std::wstringstream buffer;
  buffer << file.rdbuf();
  return ParseFlatJson(buffer.str());
}

static const wchar_t* kRequiredFields[] = {
  L"schema", L"msi_path", L"target_version", L"expected_sha256",
  L"app_pid", L"app_exe_path", L"log_path", L"state",
  L"created_at", L"attempt", L"checksum"
};

bool ValidateStateFile(const std::map<std::wstring, std::wstring>& json) {
  // Check required fields.
  for (const auto* field : kRequiredFields) {
    if (json.find(field) == json.end()) return false;
    if (json.at(field).empty()) return false;
  }

  // Validate schema version.
  int schema = 0;
  try {
    schema = std::stoi(json.at(L"schema"));
  } catch (...) {
    return false;
  }
  if (schema > 1) return false; // Future schema we don't understand.

  // Validate state value.
  const auto& state = json.at(L"state");
  const wchar_t* validStates[] = {
    L"verified", L"waitingExit", L"installing", L"installed",
    L"restarting", L"installed", L"failed", L"idle"
  };
  bool valid = false;
  for (const auto* s : validStates) {
    if (state == s) { valid = true; break; }
  }
  if (!valid) return false;

  // Validate checksum.
  if (!VerifyChecksum(json)) return false;

  return true;
}

UpdateState ParseUpdateState(const std::map<std::wstring, std::wstring>& json) {
  UpdateState s;
  s.schema         = std::stoi(json.at(L"schema"));
  s.owner          = json.count(L"owner") ? json.at(L"owner") : L"app";
  s.msiPath        = json.at(L"msi_path");
  s.targetVersion  = json.at(L"target_version");
  s.expectedSha256 = json.at(L"expected_sha256");
  s.appPid         = std::stoi(json.at(L"app_pid"));
  s.appExePath     = json.at(L"app_exe_path");
  s.logPath        = json.at(L"log_path");
  s.state          = json.at(L"state");
  s.error          = json.count(L"error") ? json.at(L"error") : L"";
  s.createdAt      = json.at(L"created_at");
  s.completedAt    = json.count(L"completed_at") ? json.at(L"completed_at") : L"";
  s.attempt        = std::stoi(json.at(L"attempt"));
  s.checksum       = json.at(L"checksum");
  return s;
}

bool WriteUpdateState(const std::wstring& path, const UpdateState& state) {
  // Build JSON string (compact, deterministic key order).
  std::wstring json;
  json += L"{";
  json += L"\"schema\":" + std::to_wstring(state.schema) + L",";
  json += L"\"owner\":\"" + state.owner + L"\",";
  json += L"\"msi_path\":\"" + state.msiPath + L"\",";
  json += L"\"target_version\":\"" + state.targetVersion + L"\",";
  json += L"\"expected_sha256\":\"" + state.expectedSha256 + L"\",";
  json += L"\"app_pid\":" + std::to_wstring(state.appPid) + L",";
  json += L"\"app_exe_path\":\"" + state.appExePath + L"\",";
  json += L"\"log_path\":\"" + state.logPath + L"\",";
  json += L"\"state\":\"" + state.state + L"\",";
  if (!state.error.empty()) {
    json += L"\"error\":\"" + state.error + L"\",";
  }
  json += L"\"created_at\":\"" + state.createdAt + L"\",";
  if (!state.completedAt.empty()) {
    json += L"\"completed_at\":\"" + state.completedAt + L"\",";
  }
  json += L"\"attempt\":" + std::to_wstring(state.attempt) + L",";

  // Compute checksum of everything except checksum field.
  std::wstring payload = json;
  // Remove trailing comma if present.
  if (payload.back() == L',') payload.pop_back();
  payload += L"}";

  std::wstring checksum = ComputeChecksum(payload);
  json += L"\"checksum\":\"" + checksum + L"\"";
  json += L"}";

  // Atomic write: temp + rename.
  std::wstring tempPath = path + L".tmp";
  {
    std::wofstream tempFile(tempPath);
    if (!tempFile.is_open()) return false;
    tempFile << json;
    tempFile.flush();
    tempFile.close();
  }

  // Delete existing file, then rename temp.
  DeleteFileW(path.c_str());
  if (!MoveFileW(tempPath.c_str(), path.c_str())) {
    // Cleanup temp on failure.
    DeleteFileW(tempPath.c_str());
    return false;
  }

  return true;
}

} // namespace ua
