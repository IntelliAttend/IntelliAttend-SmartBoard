# Release Acceptance Checklist

Every release must pass **all** gates before shipping.
Failure of any single gate blocks the release.

---

## 1. Clean Install

| # | Gate | Windows 10 22H2 | Windows 11 23H2 | Windows 11 24H2 |
|---|------|:---:|:---:|:---:|
| 1.1 | MSI installs without errors | | | |
| 1.2 | `%LOCALAPPDATA%\IntelliAttendSmartBoard\App\` contains exe + DLLs | | | |
| 1.3 | `%LOCALAPPDATA%\IntelliAttendSmartBoard\Data\` created (empty) | | | |
| 1.4 | `%LOCALAPPDATA%\IntelliAttendSmartBoard\Config\` created (empty) | | | |
| 1.5 | Start Menu shortcut created | | | |
| 1.6 | Auto-start registry key written | | | |
| 1.7 | App launches and reaches BootScreen | | | |
| 1.8 | ARP entry visible in `Add/Remove Programs` | | | |
| 1.9 | MSI log file generated with zero errors | | | |

## 2. Silent Install (Enterprise)

| # | Gate | Status |
|---|------|:------:|
| 2.1 | `msiexec /i IASB.msi /qn /norestart` completes with exit code 0 | |
| 2.2 | No UI displayed during install | |
| 2.3 | All files present in expected locations | |
| 2.4 | Auto-start registered | |
| 2.5 | `msiexec /x IASB.msi /qn` uninstalls cleanly | |

## 3. Upgrade

| # | Gate | Status |
|---|------|:------:|
| 3.1 | Upgrade from previous version completes without errors | |
| 3.2 | Old files replaced, no stale DLLs in install directory | |
| 3.3 | `%LOCALAPPDATA%\...\Data\` preserved (registration, health, state) | |
| 3.4 | `%LOCALAPPDATA%\...\Config\` preserved (env.json) | |
| 3.5 | App launches at new version after upgrade | |
| 3.6 | ARP entry updated with new version number | |
| 3.7 | Start Menu shortcut still works | |
| 3.8 | No duplicate ARP entries | |

## 4. Downgrade Blocking

| # | Gate | Status |
|---|------|:------:|
| 4.1 | Installing older version over newer version shows error | |
| 4.2 | Newer version remains intact after blocked downgrade | |

## 5. Uninstall

| # | Gate | Status |
|---|------|:------:|
| 5.1 | Uninstall completes without errors | |
| 5.2 | `App\` directory removed | |
| 5.3 | `Data\` directory preserved (user data retained) | |
| 5.4 | `Config\` directory preserved (env.json retained) | |
| 5.5 | Start Menu shortcut removed | |
| 5.6 | Auto-start registry key removed | |
| 5.7 | ARP entry removed | |
| 5.8 | Re-install after uninstall succeeds | |

## 6. Update via Agent

| # | Gate | Status |
|---|------|:------:|
| 6.1 | Update flow completes: download → verify → agent → MSI → restart | |
| 6.2 | `update_state.json` cleaned up after successful update | |
| 6.3 | `install.journal` contains full transaction record | |
| 6.4 | Event Log contains `agent_start` and `install_complete` entries | |
| 6.5 | App version matches target version after restart | |
| 6.6 | `Data\` and `Config\` preserved through update | |
| 6.7 | Heartbeat file deleted after agent completes | |
| 6.8 | Agent mutex released (second agent instance refused) | |

## 7. Update Failure Recovery

| # | Gate | Status |
|---|------|:------:|
| 7.1 | Kill app during agent handoff → app recovers on restart | |
| 7.2 | Kill agent during MSI → app detects failure, retries | |
| 7.3 | Corrupt `update_state.json` → app deletes and continues | |
| 7.4 | Simulate disk full during download → error shown, app continues | |
| 7.5 | Power loss during install → journal shows where it stopped | |

## 8. Security

| # | Gate | Status |
|---|------|:------:|
| 8.1 | MSI is Authenticode signed | |
| 8.2 | `update_agent.exe` is Authenticode signed | |
| 8.3 | Agent verifies MSI signature before install | |
| 8.4 | Agent verifies installed exe after install | |
| 8.5 | Tampered MSI rejected by agent | |

## 9. Diagnostics

| # | Gate | Status |
|---|------|:------:|
| 9.1 | Install log generated at `%TEMP%\IntelliAttend\Logs\` | |
| 9.2 | Agent log generated at `%TEMP%\IntelliAttend\Logs\` | |
| 9.3 | `install.journal` readable and complete | |
| 9.4 | Event Log entries visible in Event Viewer | |
| 9.5 | Heartbeat file created during install (if agent running) | |

## 10. Rollback

| # | Gate | Status |
|---|------|:------:|
| 10.1 | `UpdateHealthMonitor` preserves backup before update | |
| 10.2 | Crash loop after update triggers automatic rollback | |
| 10.3 | Rollback restores previous version exactly | |
| 10.4 | Previous version launches and functions after rollback | |
| 10.5 | `Data\` and `Config\` preserved through rollback | |

## 11. Interruption Safety

| # | Gate | Status |
|---|------|:------:|
| 11.1 | Kill msiexec during install → machine is bootable | |
| 11.2 | Kill agent during install → next agent run recovers | |
| 11.3 | Reboot during install → MSI rolls back automatically | |
| 11.4 | No orphaned processes after interruption | |

---

## Sign-Off

| Phase | Version | Date | Tester | Result |
|-------|---------|------|--------|--------|
| Phase 0 | | | | |
| Phase 1 | | | | |
| Phase 2 | | | | |
| Phase 3 | | | | |
| Phase 4 | | | | |
| Phase 5 | | | | |
| Phase 6 | | | | |
| Phase 7 | | | | |
| Phase 8 | | | | |

Release is **not shippable** until all gates pass and sign-off is recorded.
