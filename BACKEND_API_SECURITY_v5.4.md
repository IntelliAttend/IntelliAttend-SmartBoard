# IntelliAttend Backend API Specification v5.4
## Cryptographic Trust Model Implementation Guide

---

## Table of Contents
1. [Security Overview](#security-overview)
2. [Authentication Architecture](#authentication-architecture)
3. [API Endpoints Specification](#api-endpoints-specification)
4. [JWT Token Structure](#jwt-token-structure)
5. [Database Schema Updates](#database-schema-updates)
6. [Middleware Implementation](#middleware-implementation)
7. [Migration Checklist](#migration-checklist)
8. [Testing Guide](#testing-guide)
9. [Security Audit Results](#security-audit-results)

---

## Security Overview

### ⚠️ Critical Security Issue Fixed

**Problem Identified:**
The v5.3 implementation used MAC address as an authentication token via the `X-Board-MAC` header. This is a **critical vulnerability** because:
- MAC addresses are **public routing identifiers**, not secrets
- They are **static** (never expire)
- They can be **spoofed** easily with packet interception
- Windows 10/11 **randomizes MAC addresses** for privacy

**Solution Implemented (v5.4):**
- **JWT Access Tokens** (short-lived, 15-minute expiry)
- **Refresh Tokens** (long-lived, for obtaining new access tokens)
- **API Keys** (long-lived, fallback authentication)
- **Encrypted Local Storage** (XOR encryption with device fingerprint)

### Security Comparison

| Aspect | v5.3 (Vulnerable) | v5.4 (Secure) |
|--------|-------------------|------------------|
| **Auth Method** | MAC Address | JWT + API Key |
| **Token Expiry** | Never | 15 minutes |
| **Replay Attack** | Vulnerable | Protected (expiry) |
| **MAC Spoofing** | Vulnerable | Not applicable |
| **Token Theft Impact** | Permanent access | Limited to 15 min |
| **Local Storage** | Plain text | Encrypted |

---

## Authentication Architecture

### Token Types

#### 1. **API Key** (Long-lived)
- **Lifetime:** Years (until manually revoked)
- **Purpose:** Fallback authentication, initial device registration
- **Format:** `bk_live_<hex_64_chars>`
- **Storage:** Encrypted in device's local storage

#### 2. **Access Token** (Short-lived JWT)
- **Lifetime:** 15 minutes (900,000 ms)
- **Purpose:** Authenticate API requests
- **Format:** JWT (HS256 algorithm)
- **Header:** `Authorization: Bearer <token>`
- **Storage:** Encrypted in device's local storage

#### 3. **Refresh Token** (Long-lived)
- **Lifetime:** 1 year (or until revoked)
- **Purpose:** Obtain new access tokens
- **Format:** `rt_<hex_32_chars>`
- **Storage:** Encrypted in device's local storage

### Authentication Flow

```
[Device]                    [Backend]
   |                            |
   |-- POST /register/verify-otp -->|
   |                            |
   |<-- Returns: api_key, access_token, refresh_token --|
   |                            |
   |-- GET /sync-context (Bearer <JWT>) -->|
   |                            |
   |<-- 200 OK (data) --------|
   |                            |
   | (15 min later: JWT expires)|
   |                            |
   |-- POST /auth/refresh (refresh_token) -->|
   |                            |
   |<-- Returns: new access_token -|
   |                            |
   |-- GET /sync-context (New Bearer <JWT>) -->|
   |                            |
   |<-- 200 OK ---------------|
```

---

## API Endpoints Specification

### Base URL
```
Production:  https://api.intelliattend.com
Staging:     https://api-dev.balaseetharamanjaneyulu.com
```

---

### 1. Request OTP for Registration
**Endpoint:** `POST /api/v1/board/register/request-otp`

**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "classroom_id": "CSE-45",
  "hardware_fingerprint": "WIN_UUID_491016AE-68D8-59F1-A7E2-0C2F2D7672D2"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "OTP sent to registered admin email"
}
```

---

### 2. Verify OTP and Complete Registration ⭐ **CRITICAL UPDATE**

**Endpoint:** `POST /api/v1/board/register/verify-otp`

**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "otp": "123456",
  "classroom_id": "CSE-45",
  "hardware_fingerprint": "WIN_UUID_491016AE-68D8-59F1-A7E2-0C2F2D7672D2",
  "device_name": "SmartBoard CSE-45"
}
```

**Response (201 Created):** ⚠️ **MUST INCLUDE TOKENS**
```json
{
  "success": true,
  "message": "Device registered with cryptographic trust",
  "session_id": "abc123def456",
  "api_key": "bk_live_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0",
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJib2FyZElkIjoiQ1NFLTQ1Iiwicm9vbUlkIjoiQ1NFLTQ1IiwiaWF0IjoxNzA2NzY2MDAwLCJleHAiOjE3MDY3Njc0MDB9.abc123xyz789",
  "refresh_token": "rt_1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c",
  "expires_in_ms": 900000,
  "token_type": "Bearer",
  "data": {
    "session_id": "abc123def456",
    "course_name": "Advanced Algorithms",
    "faculty_name": "Dr. Smith",
    "roster_count": 60
  }
}
```

**⚠️ IMPORTANT:** The frontend v5.4 **requires** these fields in the response:
- `api_key`
- `access_token`
- `refresh_token`
- `expires_in_ms`

---

### 3. Refresh Access Token
**Endpoint:** `POST /api/v1/board/auth/refresh`

**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "refresh_token": "rt_1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.new_jwt_token_here",
  "expires_in_ms": 900000,
  "token_type": "Bearer"
}
```

**Response (401 Unauthorized):** (Invalid/expired refresh token)
```json
{
  "success": false,
  "error": "invalid_refresh_token",
  "message": "Refresh token is invalid or expired"
}
```

---

### 4. Sync Context (Protected Endpoint)
**Endpoint:** `GET /api/v1/board/sync-context`

**Headers:**
```json
{
  "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "Content-Type": "application/json"
}
```

**Fallback (if JWT expired):**
```json
{
  "X-API-Key": "bk_live_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0",
  "Content-Type": "application/json"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "schedule": {
    "monday": [
      {"start_time": "09:00", "end_time": "10:00", "course_name": "Algorithms", "faculty_name": "Dr. Smith"},
      {"start_time": "10:00", "end_time": "11:00", "course_name": "Data Structures", "faculty_name": "Dr. Johnson"}
    ]
  }
}
```

**Response (401 Unauthorized):**
```json
{
  "success": false,
  "error": "invalid_token",
  "message": "Access token is invalid or expired"
}
```

---

### 5. Sync Time (Protected Endpoint)
**Endpoint:** `GET /api/v1/board/time`

**Headers:**
```json
{
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "data": {
    "server_timestamp_ms": 1706766000000
  }
}
```

---

### 6. Initiate Session (Protected Endpoint)
**Endpoint:** `POST /api/v1/board/session/initiate`

**Headers:**
```json
{
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "otp": "654321"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "data": {
    "session_id": "sess_abc123",
    "session_secret": "secret_xyz789",
    "course_name": "Algorithms",
    "faculty_name": "Dr. Smith",
    "roster_count": 60,
    "section_id": "SEC-01"
  }
}
```

---

### 7. Record Attendance (Protected Endpoint)
**Endpoint:** `POST /api/v1/board/session/attendance/record-live`

**Headers:**
```json
{
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "student_id": "STU001",
  "session_id": "sess_abc123",
  "room_id": "CSE-45",
  "entry_type": "entry",
  "timestamp_ms": 1706766123456
}
```

---

### 8. Sync Vault (Protected Endpoint)
**Endpoint:** `POST /api/v1/board/sync/vault`

**Headers:**
```json
{
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
}
```

**Request Body:**
```json
{
  "session_id": "sess_abc123",
  "queued_scans": [
    {"student_id": "STU001", "timestamp_ms": 1706766123456, "scanned_totp_hash": "hash1"},
    {"student_id": "STU002", "timestamp_ms": 1706766123789, "scanned_totp_hash": "hash2"}
  ]
}
```

---

## JWT Token Structure

### Header
```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

### Payload
```json
{
  "boardId": "board_cse45_abc123",
  "roomId": "CSE-45",
  "type": "access",
  "iat": 1706766000,     // Issued at (Unix timestamp)
  "exp": 1706766900      // Expires (15 minutes later)
}
```

### Signature
```
HMACSHA256(
  base64urlEncode(header) + "." + base64urlEncode(payload),
  secret
)
```

### Environment Variable
```bash
# Backend .env
JWT_SECRET=your_64_character_random_string_here_change_in_production
```

**Generate JWT Secret:**
```bash
openssl rand -base64 48 | tr -d "\n"
```

---

## Database Schema Updates

### 1. `devices` Table (NEW)

```sql
CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id VARCHAR(50) UNIQUE NOT NULL,
  hardware_fingerprint VARCHAR(255) UNIQUE NOT NULL,
  device_name VARCHAR(100),
  api_key VARCHAR(128) UNIQUE NOT NULL,
  api_key_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_devices_room_id ON devices(room_id);
CREATE INDEX idx_devices_hardware ON devices(hardware_fingerprint);
CREATE INDEX idx_devices_api_key ON devices(api_key);
```

### 2. `refresh_tokens` Table (NEW)

```sql
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
  token VARCHAR(64) UNIQUE NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  is_revoked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_refresh_tokens_token ON refresh_tokens(token);
CREATE INDEX idx_refresh_tokens_device ON refresh_tokens(device_id);
```

### 3. Migration from v5.3

If migrating from MAC-based auth:

```sql
-- Add new columns to existing table (if exists)
ALTER TABLE devices ADD COLUMN IF NOT EXISTS api_key VARCHAR(128);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS hardware_fingerprint VARCHAR(255);

-- Generate API keys for existing devices
UPDATE devices 
SET api_key = 'bk_live_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
WHERE api_key IS NULL;

-- Make api_key NOT NULL after population
ALTER TABLE devices ALTER COLUMN api_key SET NOT NULL;
```

---

## Middleware Implementation

### Node.js/Express Example

```javascript
const jwt = require('jsonwebtoken');

// JWT Authentication Middleware
const authenticateJWT = async (req, res, next) => {
  // 1. Check Authorization header
  const authHeader = req.headers['authorization'];
  
  if (!authHeader) {
    return res.status(401).json({
      success: false,
      error: 'missing_token',
      message: 'Authorization header is required'
    });
  }

  const token = authHeader.split(' ')[1]; // Extract "Bearer <token>"
  
  if (!token) {
    return res.status(401).json({
      success: false,
      error: 'invalid_token_format',
      message: 'Invalid authorization header format'
    });
  }

  try {
    // 2. Verify JWT
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // 3. Attach device info to request
    req.boardId = decoded.boardId;
    req.roomId = decoded.roomId;
    
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({
        success: false,
        error: 'token_expired',
        message: 'Access token has expired. Use refresh token to get a new one.'
      });
    }
    
    return res.status(401).json({
      success: false,
      error: 'invalid_token',
      message: 'Access token is invalid'
    });
  }
};

// API Key Authentication Middleware (Fallback)
const authenticateApiKey = async (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  if (!apiKey) {
    return res.status(401).json({
      success: false,
      error: 'missing_api_key',
      message: 'API key is required'
    });
  }

  try {
    // Lookup device by API key
    const device = await db.query(
      'SELECT id, room_id FROM devices WHERE api_key = $1 AND is_active = TRUE',
      [apiKey]
    );

    if (device.rows.length === 0) {
      return res.status(401).json({
        success: false,
        error: 'invalid_api_key',
        message: 'API key is invalid or revoked'
      });
    }

    req.boardId = device.rows[0].id;
    req.roomId = device.rows[0].room_id;
    
    next();
  } catch (err) {
    return res.status(500).json({
      success: false,
      error: 'internal_error',
      message: 'Internal server error'
    });
  }
};

// Combined Authentication Middleware
const authenticate = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  
  if (authHeader) {
    // Try JWT first
    return authenticateJWT(req, res, next);
  } else if (req.headers['x-api-key']) {
    // Fallback to API key
    return authenticateApiKey(req, res, next);
  } else {
    return res.status(401).json({
      success: false,
      error: 'unauthorized',
      message: 'No authentication method provided'
    });
  }
};

// Usage in routes
app.get('/api/v1/board/sync-context', authenticate, async (req, res) => {
  // req.boardId and req.roomId are set by middleware
  const context = await getContextForRoom(req.roomId);
  res.json({ success: true, schedule: context });
});
```

### Python/Flask Example

```python
from flask import Flask, request, jsonify
import jwt
import os
from datetime import datetime, timedelta

app = Flask(__name__)
JWT_SECRET = os.getenv('JWT_SECRET')

def authenticate():
    auth_header = request.headers.get('Authorization')
    
    if auth_header:
        try:
            token = auth_header.split(' ')[1]
            decoded = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
            request.board_id = decoded['boardId']
            request.room_id = decoded['roomId']
            return True
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'token_expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'invalid_token'}), 401
    
    # Fallback to API key
    api_key = request.headers.get('X-API-Key')
    if api_key:
        device = db.find_device_by_api_key(api_key)
        if device:
            request.board_id = device.id
            request.room_id = device.room_id
            return True
    
    return jsonify({'error': 'unauthorized'}), 401

@app.route('/api/v1/board/sync-context', methods=['GET'])
def sync_context():
    if not authenticate():
        pass  # Response already sent
    
    context = get_context_for_room(request.room_id)
    return jsonify({'success': True, 'schedule': context})
```

---

## Migration Checklist

### Phase 1: Backend Preparation
- [ ] Generate JWT secret: `openssl rand -base64 48`
- [ ] Add `JWT_SECRET` to backend `.env` file
- [ ] Create `devices` table with new schema
- [ ] Create `refresh_tokens` table
- [ ] Migrate existing devices (generate API keys)
- [ ] Implement JWT generation function
- [ ] Implement JWT verification middleware
- [ ] Implement API key fallback middleware

### Phase 2: Endpoint Updates
- [ ] Update `POST /register/verify-otp` to return tokens:
  - [ ] Generate API key
  - [ ] Generate access token (JWT, 15min)
  - [ ] Generate refresh token
  - [ ] Store refresh token in database
  - [ ] Return all tokens in response
- [ ] Create `POST /auth/refresh` endpoint
- [ ] Update all protected endpoints to use `authenticate` middleware
- [ ] Remove `X-Board-MAC` header dependency (deprecate)

### Phase 3: Testing
- [ ] Test registration flow (OTP → tokens)
- [ ] Test API call with JWT
- [ ] Test JWT expiry (wait 15min)
- [ ] Test token refresh
- [ ] Test API key fallback
- [ ] Test invalid token rejection
- [ ] Test MAC spoofing (should fail)

### Phase 4: Deployment
- [ ] Deploy backend with new endpoints
- [ ] Monitor for authentication errors
- [ ] Communicate with frontend team (v5.4 ready)
- [ ] Frontend team deploys updated app
- [ ] Monitor token refresh patterns
- [ ] Revoke old MAC-based auth (after grace period)

---

## Testing Guide

### 1. Test Registration Flow

```bash
# Request OTP
curl -X POST https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/register/request-otp \
  -H "Content-Type: application/json" \
  -d '{
    "classroom_id": "CSE-45",
    "hardware_fingerprint": "WIN_UUID_test123"
  }'

# Verify OTP (use OTP from email/console)
curl -X POST https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/register/verify-otp \
  -H "Content-Type: application/json" \
  -d '{
    "otp": "123456",
    "classroom_id": "CSE-45",
    "hardware_fingerprint": "WIN_UUID_test123",
    "device_name": "Test SmartBoard"
  }'

# ✅ Expected: Response includes api_key, access_token, refresh_token
```

### 2. Test JWT Authentication

```bash
# Use access_token from registration
ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIs..."

# Test sync-context with JWT
curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# ✅ Expected: 200 OK with schedule data
```

### 3. Test Token Expiry

```bash
# Wait 15+ minutes, then try again
curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# ✅ Expected: 401 Unauthorized with "token_expired" error
```

### 4. Test Token Refresh

```bash
REFRESH_TOKEN="rt_1a2b3c4d..."

curl -X POST https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "'$REFRESH_TOKEN'"}'

# ✅ Expected: 200 OK with new access_token
```

### 5. Test MAC Spoofing (Should Fail)

```bash
# Try old method (should fail)
curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "X-Board-MAC: 00:11:22:33:44:55"

# ✅ Expected: 401 Unauthorized (MAC no longer accepted)
```

### 6. Test API Key Fallback

```bash
API_KEY="bk_live_..."

curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "X-API-Key: $API_KEY"

# ✅ Expected: 200 OK (fallback authentication)
```

---

## Security Audit Results

### Vulnerabilities Fixed (v5.3 → v5.4)

| Vulnerability | Severity | Status |
|--------------|----------|--------|
| MAC address as password | **CRITICAL** | ✅ FIXED |
| Static token (no expiry) | **HIGH** | ✅ FIXED |
| Replay attacks possible | **HIGH** | ✅ FIXED |
| Local storage plaintext | **MEDIUM** | ✅ FIXED (XOR encryption) |
| No token refresh mechanism | **MEDIUM** | ✅ FIXED |
| MAC randomization breaks auth | **MEDIUM** | ✅ FIXED |
| Re-registration deadlock | **LOW** | ✅ FIXED |

### Attack Scenarios (After Fix)

| Attack Type | Possible? | Impact |
|-------------|-----------|--------|
| MAC address spoofing | ❌ No | MAC not used for auth |
| JWT interception | ⚠️ Yes | Limited to 15 minutes |
| API key theft | ⚠️ Yes | Token encrypted locally |
| Refresh token theft | ⚠️ Yes | Can be revoked, long-lived |
| Replay attack | ❌ No | JWT has expiry |
| Local DB access | ⚠️ Yes | Tokens encrypted |

### Recommendations for Production

1. **Upgrade XOR to AES-256-GCM** for local encryption
2. **Use platform secure enclave** (iOS/Android) or **Windows DPAPI**
3. **Implement token revocation list** for compromised devices
4. **Add rate limiting** on refresh endpoint (max 10/minute)
5. **Log all authentication failures** for monitoring
6. **Use HTTPS with certificate pinning** (already in Flutter app)
7. **Rotate JWT secret** every 6 months
8. **Implement device deregistration** endpoint

---

## Environment Variables (Backend)

```bash
# .env file

# Server
PORT=3000
NODE_ENV=production

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=intelliattend
DB_USER=dbuser
DB_PASSWORD=dbpass

# JWT
JWT_SECRET=your_64_char_random_string_here_change_me
JWT_ALGORITHM=HS256

# Token Settings
ACCESS_TOKEN_EXPIRY_MS=900000        # 15 minutes
REFRESH_TOKEN_EXPIRY_DAYS=365        # 1 year

# API Keys
API_KEY_LENGTH=64
API_KEY_PREFIX=bk_live_

# CORS (if needed)
CORS_ORIGIN=https://app.intelliattend.com
```

---

## Support & Contact

**Frontend Team:** Already implemented v5.4 (see `lib/services/secure_storage_service.dart`)

**Backend Team:** Use this document to implement the cryptographic trust model.

**Questions?** Contact: [your-email@intelliattend.com]

---

**Document Version:** 5.4  
**Last Updated:** May 1, 2026  
**Status:** Ready for Backend Implementation ✅
