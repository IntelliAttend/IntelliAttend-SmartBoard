# PII Retention Policy (O11)

## Scope
This policy covers personally identifiable information (PII) stored or processed by the IntelliAttend SmartBoard system.

## Data Collected
| Data | Location | Retention |
|------|----------|-----------|
| Student IDs | Isar local vault, Firestore ActiveSessions | Cleared when session terminates. Hard-deleted after 30 days. |
| Attendance timestamps | Firestore attendance subcollection | 90 days (configurable per institution policy) |
| Device fingerprints | Firestore smart_boards collection | Until device is deregistered |
| Heartbeat logs | Firestore board_heartbeats | 7 days (TTL index on `last_heartbeat_at`) |

## Auto-Purge Mechanism
Firestore TTL policies are configured on:
- `board_heartbeats` → delete after 7 days
- `Sessions/{id}/attendance` → delete after 90 days

## Manual Wipe
Endpoint: `POST /api/v1/device/deregister`  
Removes all device PII from Firestore and clears local Isar vault.
