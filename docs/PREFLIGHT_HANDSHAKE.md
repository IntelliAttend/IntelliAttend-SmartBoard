# Pre-Flight Warm-Up Handshake

**Status:** WORKING (SmartBoard client + Backend API)  
**Scope:** SmartBoard Client → Backend API → Firestore  
**Objective:** Pre-allocate a session ID before faculty enters OTP, enabling QR generation without API latency.

---

## 1. The Flow

```
T-3 ──┐
       ├── SmartBoard calls  GET /api/v1/board/preflight?slot_id=<slotId>
       │   (via _buildUri with typed queryParameters map)
       │
       ├── Backend MUST:
       │    1. Create a document in Firestore  ActiveSessions/<sessionId>
       │       with  status: "pre-allocated"  and  smart_board_id: <boardId>
       │    2. Return HTTP 200 with:
       │         {
       │           "pre_allocated_session_id": "<sessionId>",
       │           "server_timestamp": <unix_ms>
       │         }
       │
       ├── SmartBoard receives 200 → stores  pre_allocated_session_id
       │     in  _preAllocatedSessionId  and sets  _preFlightStatus = ready
       │     UI shows  "System Ready"
       │
       └── Firestore stream (watchActiveSession) picks up the doc
            → _handleIncomingSession → Case A
            (redundant confirmation; the API response is authoritative)

T-0 ──┐
       ├── Orchestrator forces KioskMode.locked (full-screen takeover)
       │
T+any ─┤
       ├── Faculty enters PIN → _handleVerifyOtp()
       │    reads  _preAllocatedSessionId  (must be non-null)
       │    calls  POST /api/v1/board/session/initiate  with OTP
       │    uses the pre-allocated session ID (ignores API response's session_id)
       │    derives session_secret via split-knowledge
       │    navigates to AttendanceScreen
       └
```

---

## 2. History: The URL Encoding Bug (Fixed)

The pre-flight endpoint was **always present** on the backend. SmartBoard was mangling the URL by passing `?` embedded in the path string through `Uri.replace(path:)`, which percent-encoded `?` as `%3F`. The server received a path with no query string and returned 404.

### Original buggy code (`api_service.dart` — old `_buildUri`):
```dart
// OLD: path = "api/v1/board/preflight?slot_id=SLOT_..."
// Uri.replace(path:) percent-encodes ? -> %3F
// Server sees path "/api/v1/board/preflight%3Fslot_id=..." — NO query params
```
**Root cause:** `_buildUri()` used `Uri.replace(path: rawPath)` which only sets the path component. Any `?` in the path was encoded as `%3F`, so query parameters were never parsed.

### Current correct `_buildUri` (`api_service.dart:64-79`):
```dart
static Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
  final base = AppConfig.apiBaseUrl;
  final cleanPath = path.startsWith('/') ? path.substring(1) : path;

  if (queryParameters != null && queryParameters.isNotEmpty) {
    return Uri.parse('$base/$cleanPath').replace(queryParameters: queryParameters);
  }
  return Uri.parse('$base/$cleanPath');
}
```

Query parameters are now passed as a typed `Map<String, String>` and forwarded through `Uri.replace(queryParameters:)`. The chain is:

```
_getPreFlight() → _request('GET', path, queryParameters: {...})
               → _executeWithRetry() → _buildUri(path, queryParameters: {...})
```

---

## 3. Current Behavior

### Pre-flight confirmed working:
```
GET api/v1/board/preflight?slot_id=SLOT_CSE-AIML-A_2025_Tuesday_P6
→ 200 {"pre_allocated_session_id": "38008fafa1199767a148", "server_timestamp": ...}
```

Board logs: `[Idle] Board ARMED. SessionID in RAM: 38008fafa1199767a148. Waiting for faculty PIN...`

### UI Status Mapping:
| `_preFlightStatus` | UI Display | When Set |
|---|---|---|
| `none` | "PENDING" (grey) | Initial, or preflight not yet attempted |
| `connecting` | "CONNECTING..." (yellow) | During API call |
| `ready` | "System Ready" (green) | Only on successful API response pre-flight |
| (never set from Firestore alone) | | |

### Retry behavior:
- Pre-flight retries up to **5 times** at ~20s intervals with ±3s jitter
- After exhaustion: `_handleVerifyOtp()` falls back to `initiateSession` API response's `session_id`
- Faculty can always proceed manually via PIN regardless of pre-flight status

### Stale Firestore ActiveSessions doc — guarded (`idle_screen.dart:317-350`):
`_handleIncomingSession` now validates:
1. If `created_at` field exists and is older than 2 hours → reject (log warning, return)
2. If `slot_id` field exists and doesn't match any current/upcoming timeline entry → reject
3. Crash-recovery sessions (Case B, has session secret in SecureStorage) bypass both checks

---

## 4. SmartBoard Code Paths

### File: `lib/services/api_service.dart:393-407`
```dart
static Future<Map<String, dynamic>> getPreFlight(String slotId, {int retryCount = 1}) async {
  final response = await _request('GET', 'api/v1/board/preflight',
      queryParameters: {'slot_id': slotId});
  if (response.statusCode != 200) throw _apiError('Pre-flight Handshake', response);
  return jsonDecode(response.body);
}
```

### File: `lib/services/api_service.dart:96-107`
```dart
static Future<http.Response> _request(String method, String path,
    {Map<String, String>? queryParameters, ...}) async {
  return _executeWithRetry(method, path, queryParameters: queryParameters, ...);
}
```

### File: `lib/services/pre_flight_service.dart:154-208`
```dart
static const int _maxWarmUpRetries = 5;

Future<Map<String, dynamic>?> runPerSessionWarmUp(String slotId, {bool isRetry = false}) async {
  // Retries up to _maxWarmUpRetries (5), then stops
  // Returns null on exhaustion → faculty proceeds via PIN fallback
}
```

### File: `lib/presentation/screens/idle_screen.dart:552-592`
```dart
void _triggerWarmUp(String slotId, {bool force = false}) async {
  final result = await PreFlightService().runPerSessionWarmUp(slotId);
  if (result != null && result['status'] == 'ready') {
    _preFlightStatus = PreFlightStatus.ready;
    _preAllocatedSessionId = result['pre_allocated_session_id'];
  }
}
```

### File: `lib/presentation/screens/idle_screen.dart:317-385`
```dart
void _handleIncomingSession(Map<String, dynamic> data) async {
  // Case A (no session secret): stores session ID in _preAllocatedSessionId
  //    after stale doc guard (created_at < 2h, slot_id matches timeline)
  // Case B (has session secret): crash-recovery → navigates to AttendanceScreen
}
```

### File: `lib/presentation/screens/idle_screen.dart:595-650`
```dart
Future<void> _handleVerifyOtp() async {
  // Uses _preAllocatedSessionId if non-null
  // Falls back to initiateSession API response's session_id if null
}
```

---

## 5. Firewall/Routing Notes (Windows Kiosk)

If the pre-flight handshake or any API call fails with a network error, verify:

1. **Windows Firewall** — ensure the process `smartboard.exe` (or Flutter's `windows/runner/Debug/smartboard.exe`) is allowed through **both**:
   - Inbound rules (TCP)
   - Outbound rules (TCP)
2. **Corporate Proxy** — the backend URL may require a PAC file or manual proxy configuration
3. **Self-signed certificates** — Flutter Windows uses the OS certificate store. If the backend uses a self-signed cert, install it in **Trusted Root Certification Authorities**.

---

## 6. Files Referenced

| File | Role |
|---|---|
| `lib/services/api_service.dart:64-79` | `_buildUri()` — query parameters via typed Map |
| `lib/services/api_service.dart:96-107` | `_request()` — forwards queryParameters through chain |
| `lib/services/api_service.dart:393-407` | `getPreFlight()` — HTTP call with `queryParameters` |
| `lib/services/pre_flight_service.dart:17-20` | `_maxWarmUpRetries = 5` — retry cap |
| `lib/services/pre_flight_service.dart:154-208` | `runPerSessionWarmUp()` — retry logic with cap |
| `lib/presentation/screens/idle_screen.dart:317-385` | `_handleIncomingSession()` — stale doc guard + crash recovery |
| `lib/presentation/screens/idle_screen.dart:552-592` | `_triggerWarmUp()` — status update from API |
| `lib/presentation/screens/idle_screen.dart:595-650` | `_handleVerifyOtp()` — PIN flow with pre-allocated ID fallback |
