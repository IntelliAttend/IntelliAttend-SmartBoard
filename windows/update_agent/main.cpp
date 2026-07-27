#include <windows.h>
#include <string>
#include <sstream>

#include "common.h"
#include "json_reader.h"
#include "logger.h"
#include "checksum.h"
#include "file_utils.h"
#include "process_watcher.h"
#include "installer.h"
#include "version_checker.h"
#include "launcher.h"
#include "singleton.h"
#include "heartbeat.h"
#include "install_journal.h"
#include "authenticode.h"
#include "session.h"
#include "event_log.h"

namespace ua {

// State name strings for logging.
static const wchar_t* StateName(State s) {
  switch (s) {
    case State::Boot:             return L"BOOT";
    case State::Reading:          return L"READING";
    case State::WaitingAppExit:   return L"WAITING";
    case State::Installing:       return L"INSTALLING";
    case State::Verifying:        return L"VERIFYING";
    case State::Restarting:       return L"RESTARTING";
    case State::Cleanup:          return L"CLEANUP";
    case State::Done:             return L"DONE";
  }
  return L"UNKNOWN";
}

// Write state file and update the in-memory state.
static bool SaveState(const std::wstring& path, UpdateState& state,
                       const std::wstring& newState,
                       const std::wstring& error = L"") {
  state.state = newState;
  state.owner = L"agent";
  if (!error.empty()) state.error = error;
  if (newState == L"failed" || newState == L"installed") {
    SYSTEMTIME st;
    GetSystemTime(&st);
    wchar_t buf[64];
    swprintf_s(buf, L"%04d-%02d-%02dT%02d:%02d:%02d.000Z",
               st.wYear, st.wMonth, st.wDay,
               st.wHour, st.wMinute, st.wSecond);
    state.completedAt = buf;
  }
  return WriteUpdateState(path, state);
}

// ── State: Boot ──────────────────────────────────────────────────────────

static bool DoBoot(const std::wstring& statePath, UpdateState& /*state*/) {
  UA_LOG_INFO(StateName(State::Boot), L"update_agent.exe starting");

  // Acquire singleton mutex — only one agent may run.
  if (!SingletonGuard::Acquire()) {
    UA_LOG_ERROR(StateName(State::Boot), L"Another agent instance is running, exiting");
    return false;
  }

  // Initialize event log.
  EventLog::Register();

  // Initialize install journal.
  std::wstring journalPath = statePath;
  size_t lastSlash = journalPath.find_last_of(L"\\/");
  if (lastSlash != std::wstring::npos) {
    journalPath = journalPath.substr(0, lastSlash) + L"\\install.journal";
  } else {
    journalPath = L"install.journal";
  }
  InstallJournal::Init(journalPath);
  InstallJournal::Record(L"agent_start");

  // Log system info.
  wchar_t buf[256];
  swprintf_s(buf, L"PID=%lu, version=%s", GetCurrentProcessId(), kAgentVersion);
  UA_LOG_INFO(StateName(State::Boot), buf);

  // Check console session.
  if (!IsConsoleSessionActive()) {
    UA_LOG_WARN(StateName(State::Boot), L"No active console session, continuing anyway");
  }

  return true;
}

// ── State: Reading ───────────────────────────────────────────────────────

static bool DoReading(const std::wstring& statePath, UpdateState& state) {
  UA_LOG_INFO(StateName(State::Reading), L"Parsing update_state.json");

  if (!FileExists(statePath)) {
    UA_LOG_ERROR(StateName(State::Reading), L"update_state.json not found");
    return false;
  }

  auto json = ReadJson(statePath);
  if (json.empty()) {
    UA_LOG_ERROR(StateName(State::Reading), L"update_state.json is empty or invalid JSON");
    return false;
  }

  if (!ValidateStateFile(json)) {
    UA_LOG_ERROR(StateName(State::Reading), L"Validation failed (checksum, schema, or required fields)");
    return false;
  }

  state = ParseUpdateState(json);

  // Verify installer file exists.
  if (!FileExists(state.installerPath)) {
    UA_LOG_ERROR(StateName(State::Reading), L"Installer file not found");
    return false;
  }

  // Verify installer size is reasonable (> 1MB).
  uint64_t installerSize = FileSize(state.installerPath);
  if (installerSize < 1024 * 1024) {
    UA_LOG_ERROR(StateName(State::Reading), L"Installer file too small, likely corrupt");
    return false;
  }

  // Verify Authenticode signature of installer.
  UA_LOG_INFO(StateName(State::Reading), L"Verifying Authenticode signature");
  if (!VerifyAuthenticode(state.installerPath)) {
    UA_LOG_ERROR(StateName(State::Reading), L"Installer Authenticode signature invalid or unsigned");
    InstallJournal::Record(L"authenticode_fail", false, state.installerPath);
    EventLog::Error(L"Update installer failed Authenticode verification");
    return false;
  }
  UA_LOG_INFO(StateName(State::Reading), L"Authenticode signature valid");

  wchar_t buf[256];
  swprintf_s(buf, L"Schema v%d, state=%s, target=%s, app_pid=%d",
             state.schema, state.state.c_str(),
             state.targetVersion.c_str(), state.appPid);
  UA_LOG_INFO(StateName(State::Reading), buf);

  UA_LOG_INFO(StateName(State::Reading), L"Checksum valid, installer verified");
  InstallJournal::Record(L"read_complete", true, state.targetVersion);
  return true;
}

// ── State: Waiting for App Exit ──────────────────────────────────────────

static bool DoWaitingAppExit(UpdateState& state) {
  wchar_t buf[128];
  swprintf_s(buf, L"Watching app PID=%d", state.appPid);
  UA_LOG_INFO(StateName(State::WaitingAppExit), buf);

  // Restart Manager integration deferred to future version.
  // The existing wait-and-terminate fallback handles locked processes.
  UA_LOG_INFO(StateName(State::WaitingAppExit), L"Waiting for application to exit (no Restart Manager)");

  // Check if app is already gone.
  if (!IsProcessRunning(state.appPid)) {
    UA_LOG_INFO(StateName(State::WaitingAppExit), L"App already exited");
    InstallJournal::Record(L"app_exit_detected");
    return true;
  }

  // Wait for app to exit.
  bool exited = WaitForProcessExit(state.appPid, kWaitForAppExitMs);

  if (!exited) {
    // Try to terminate.
    UA_LOG_WARN(StateName(State::WaitingAppExit),
                L"App still running after timeout, attempting TerminateProcess");
    TerminateProcessById(state.appPid);

    exited = WaitForProcessExit(state.appPid, 5000);
    if (!exited) {
      UA_LOG_ERROR(StateName(State::WaitingAppExit),
                   L"Failed to terminate app process");
      EventLog::Error(L"Update agent could not terminate application process");
      return false;
    }
  }

  UA_LOG_INFO(StateName(State::WaitingAppExit), L"App exited");
  InstallJournal::Record(L"app_exit_confirmed");
  return true;
}

// ── State: Installing ────────────────────────────────────────────────────

static bool DoInstalling(const std::wstring& statePath, UpdateState& state) {
  // Initialize heartbeat for watchdog.
  std::wstring heartbeatPath = statePath;
  size_t lastSlash = heartbeatPath.find_last_of(L"\\/");
  if (lastSlash != std::wstring::npos) {
    heartbeatPath = heartbeatPath.substr(0, lastSlash) + L"\\agent_heartbeat.txt";
  } else {
    heartbeatPath = L"agent_heartbeat.txt";
  }
  Heartbeat::Init(heartbeatPath);
  Heartbeat::Pulse();

  InstallJournal::Record(L"install_start");

  for (int attempt = 1; attempt <= kInstallMaxRetries; attempt++) {
    state.attempt = attempt;
    SaveState(statePath, state, L"installing");
    Heartbeat::Pulse();

    wchar_t buf[256];
    swprintf_s(buf, L"Attempt %d/%d, setup.exe /SILENT \"%s\" /LOG \"%s\"",
               attempt, kInstallMaxRetries, state.installerPath.c_str(), state.logPath.c_str());
    UA_LOG_INFO(StateName(State::Installing), buf);

    DWORD exitCode = RunSetupExe(state.installerPath, state.logPath);
    Heartbeat::Pulse();

    wchar_t exitBuf[64];
    swprintf_s(exitBuf, L"setup.exe exited with code %lu", exitCode);
    UA_LOG_INFO(StateName(State::Installing), exitBuf);

    if (IsInstallSuccess(exitCode)) {
      InstallJournal::Record(L"install_complete", true,
                             L"exit_code=" + std::to_wstring(exitCode));
      EventLog::Info(L"Installation completed successfully");
      Heartbeat::Stop();
      return true;
    }

    InstallJournal::Record(L"install_attempt_failed", false,
                           L"exit_code=" + std::to_wstring(exitCode));

    if (attempt < kInstallMaxRetries && IsInstallRetryable(exitCode)) {
      wchar_t retryBuf[128];
      swprintf_s(retryBuf, L"Retry %d/%d in %lu seconds",
                 attempt + 1, kInstallMaxRetries, kInstallRetryDelays[attempt] / 1000);
      UA_LOG_WARN(StateName(State::Installing), retryBuf);
      Sleep(kInstallRetryDelays[attempt]);
      Heartbeat::Pulse();
      continue;
    }

    // Non-retryable or all retries exhausted.
    wchar_t errBuf[128];
    swprintf_s(errBuf, L"All retries exhausted, last exit code=%lu", exitCode);
    UA_LOG_ERROR(StateName(State::Installing), errBuf);
    InstallJournal::Record(L"install_failed", false, errBuf);
    EventLog::Error(L"Installation failed after all retries");
    Heartbeat::Stop();
    return false;
  }

  Heartbeat::Stop();
  return false;
}

// ── State: Verifying ─────────────────────────────────────────────────────

static bool DoVerifying(UpdateState& state) {
  UA_LOG_INFO(StateName(State::Verifying), L"Checking installed executable");

  // Wait for exe to appear (installer may still be flushing).
  DWORD waited = 0;
  while (!FileExists(state.appExePath) && waited < kExePollTimeoutMs) {
    Sleep(500);
    waited += 500;
  }

  if (!FileExists(state.appExePath)) {
    UA_LOG_ERROR(StateName(State::Verifying), L"New exe not found after install");
    return false;
  }

  // Verify version.
  if (!VerifyInstalledVersion(state.appExePath, state.targetVersion)) {
    std::wstring actual = GetFileVersion(state.appExePath);
    wchar_t buf[256];
    swprintf_s(buf, L"Version mismatch: expected=%s, actual=%s",
               state.targetVersion.c_str(), actual.c_str());
    UA_LOG_ERROR(StateName(State::Verifying), buf);
    EventLog::Error(L"Post-install version verification failed");
    return false;
  }

  // Verify Authenticode of installed exe.
  if (!VerifyAuthenticode(state.appExePath)) {
    UA_LOG_ERROR(StateName(State::Verifying), L"Installed exe failed Authenticode verification");
    EventLog::Error(L"Installed executable failed Authenticode verification");
    return false;
  }

  wchar_t buf[128];
  swprintf_s(buf, L"Version %s matches target, Authenticode valid", state.targetVersion.c_str());
  UA_LOG_INFO(StateName(State::Verifying), buf);
  InstallJournal::Record(L"verify_complete", true, state.targetVersion);
  return true;
}

// ── State: Restarting ────────────────────────────────────────────────────

static bool DoRestarting(const std::wstring& statePath, UpdateState& state) {
  SaveState(statePath, state, L"restarting");

  wchar_t buf[256];
  swprintf_s(buf, L"Launching %s --intelliattend-autostart", state.appExePath.c_str());
  UA_LOG_INFO(StateName(State::Restarting), buf);

  DWORD newPid = 0;
  if (!LaunchApp(state.appExePath, &newPid)) {
    UA_LOG_ERROR(StateName(State::Restarting), L"Failed to launch new app process");
    EventLog::Error(L"Failed to restart application after update");
    return false;
  }

  wchar_t pidBuf[64];
  swprintf_s(pidBuf, L"New process started, PID=%lu", newPid);
  UA_LOG_INFO(StateName(State::Restarting), pidBuf);
  InstallJournal::Record(L"restart_complete", true, L"pid=" + std::to_wstring(newPid));
  return true;
}

// ── State: Cleanup ───────────────────────────────────────────────────────

static bool DoCleanup(const std::wstring& statePath, UpdateState& state) {
  UA_LOG_INFO(StateName(State::Cleanup), L"Deleting installer and updating state");

  if (!DeleteFileSafe(state.installerPath)) {
    UA_LOG_WARN(StateName(State::Cleanup), L"Failed to delete installer (non-fatal)");
  }

  SaveState(statePath, state, L"installed");
  InstallJournal::Record(L"cleanup_complete");
  EventLog::Info(L"Update completed successfully");

  return true;
}

} // namespace ua

// ── Entry Point ──────────────────────────────────────────────────────────

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  using namespace ua;

  // Parse command line for state file path.
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);

  std::wstring statePath;
  if (argc >= 2 && argv) {
    statePath = argv[1];
  }
  if (argv) LocalFree(argv);

  if (statePath.empty()) {
    wchar_t localAppData[MAX_PATH];
    if (GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH)) {
      statePath = std::wstring(localAppData) +
                  L"\\IntelliAttendSmartBoard\\Data\\update_state.json";
    } else {
      return ExitCode::InvalidState;
    }
  }

  // ── BOOT ─────────────────────────────────────────────────────────────

  State currentState = State::Boot;
  UpdateState state;

  if (!DoBoot(statePath, state)) {
    return ExitCode::InvalidState;
  }

  // ── READING ──────────────────────────────────────────────────────────

  currentState = State::Reading;
  if (!DoReading(statePath, state)) {
    EventLog::Error(L"Update state file validation failed");
    SingletonGuard::Release();
    return ExitCode::InvalidState;
  }

  // Initialize logger with the path from the state file.
  Logger::Instance().Init(state.logPath);
  UA_LOG_INFO(StateName(State::Boot), L"update_agent.exe started, logger initialized");
  wchar_t versionBuf[128];
  swprintf_s(versionBuf, L"PID=%lu, version=%s, state_path=%s",
             GetCurrentProcessId(), kAgentVersion, statePath.c_str());
  UA_LOG_INFO(StateName(State::Boot), versionBuf);

  DWORD startTime = GetTickCount();
  EventLog::Info(L"Update agent started");

  // ── WAITING FOR APP EXIT ────────────────────────────────────────────

  currentState = State::WaitingAppExit;
  if (!DoWaitingAppExit(state)) {
    SaveState(statePath, state, L"failed", L"App exit timeout");
    Logger::Instance().Error(StateName(currentState), L"Exiting with code 1");
    EventLog::Error(L"Update agent: application exit timeout");
    Logger::Instance().Close();
    SingletonGuard::Release();
    return ExitCode::AppExitTimeout;
  }

  // ── INSTALLING ─────────────────────────────────────────────────────

  currentState = State::Installing;
  if (!DoInstalling(statePath, state)) {
    SaveState(statePath, state, L"failed", L"Install failed");
    Logger::Instance().Error(StateName(currentState), L"Exiting with code 2");
    EventLog::Error(L"Update agent: installation failed");
    Logger::Instance().Close();
    SingletonGuard::Release();
    return ExitCode::InstallFail;
  }

  // ── VERIFYING ──────────────────────────────────────────────────────

  currentState = State::Verifying;
  SaveState(statePath, state, L"installed");
  if (!DoVerifying(state)) {
    SaveState(statePath, state, L"failed", L"Post-install verification failed");
    Logger::Instance().Error(StateName(currentState), L"Exiting with code 3");
    EventLog::Error(L"Update agent: post-install verification failed");
    Logger::Instance().Close();
    SingletonGuard::Release();
    return ExitCode::VerifyFailed;
  }

  // ── RESTARTING ─────────────────────────────────────────────────────

  currentState = State::Restarting;
  if (!DoRestarting(statePath, state)) {
    SaveState(statePath, state, L"failed", L"App restart failed");
    Logger::Instance().Error(StateName(currentState), L"Exiting with code 4");
    EventLog::Error(L"Update agent: application restart failed");
    Logger::Instance().Close();
    SingletonGuard::Release();
    return ExitCode::RestartFailed;
  }

  // ── CLEANUP ────────────────────────────────────────────────────────

  currentState = State::Cleanup;
  DoCleanup(statePath, state);

  // ── DONE ───────────────────────────────────────────────────────────

  currentState = State::Done;
  DWORD elapsed = GetTickCount() - startTime;
  wchar_t doneBuf[128];
  swprintf_s(doneBuf, L"Update complete in %lu.%lus, exiting", elapsed / 1000, (elapsed / 100) % 10);
  UA_LOG_INFO(StateName(State::Done), doneBuf);

  EventLog::Info(L"Update agent completed successfully");

  // Clean up.
  InstallJournal::Record(L"agent_complete");
  EventLog::Unregister();
  Logger::Instance().Close();
  SingletonGuard::Release();

  return ExitCode::Success;
}
