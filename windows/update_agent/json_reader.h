#pragma once

#include <string>
#include <map>
#include "common.h"

namespace ua {

// Minimal JSON reader for update_state.json.
// Handles flat objects only (no nested objects/arrays).
// Returns empty map on parse failure.
std::map<std::wstring, std::wstring> ReadJson(const std::wstring& path);

// Validate that all required fields are present and non-empty.
bool ValidateStateFile(const std::map<std::wstring, std::wstring>& json);

// Populate UpdateState from parsed JSON.
UpdateState ParseUpdateState(const std::map<std::wstring, std::wstring>& json);

// Write update_state.json atomically (temp + rename).
bool WriteUpdateState(const std::wstring& path, const UpdateState& state);

} // namespace ua
