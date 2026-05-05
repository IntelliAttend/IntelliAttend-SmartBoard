# 🚀 Quick Start: Backend v5.4 Implementation

## What You Need to Do (Summary)

The frontend (v5.4) **NO LONGER** accepts MAC address authentication. You must implement cryptographic tokens.

---

## 1. Minimal Changes Required (MVP)

### Step 1: Add JWT Library
```bash
# Node.js
npm install jsonwebtoken

# Python
pip install PyJWT
```

### Step 2: Generate JWT Secret
```bash
openssl rand -base64 48
```
Add to your `.env`:
```
JWT_SECRET=output_from_above_command
```

### Step 3: Update Registration Response

**File:** `routes/board.js` or similar

**OLD Response (DELETE):**
```javascript
res.json({
  success: true,
  session_id: "abc123",
  message: "Device registered"
});
```

**NEW Response (IMPLEMENT):**
```javascript
const jwt = require('jsonwebtoken');

// Generate tokens
const apiKey = 'bk_live_' + crypto.randomBytes(48).toString('hex');
const refreshToken = 'rt_' + crypto.randomBytes(24).toString('hex');
const accessToken = jwt.sign(
  { boardId: device.id, roomId: device.room_id, type: 'access' },
  process.env.JWT_SECRET,
  { expiresIn: '15m' }
);

// Save to database
await db.query(
  'INSERT INTO refresh_tokens (device_id, token, expires_at) VALUES ($1, $2, $3)',
  [device.id, refreshToken, new Date(Date.now() + 365*24*60*60*1000)]
);

res.status(201).json({
  success: true,
  api_key: apiKey,
  access_token: accessToken,
  refresh_token: refreshToken,
  expires_in_ms: 900000,  // 15 minutes
  token_type: 'Bearer',
  session_id: "abc123",
  message: "Device registered with cryptographic trust"
});
```

### Step 4: Create Refresh Endpoint

**NEW Endpoint:** `POST /api/v1/board/auth/refresh`

```javascript
app.post('/api/v1/board/auth/refresh', async (req, res) => {
  const { refresh_token } = req.body;
  
  if (!refresh_token) {
    return res.status(400).json({ error: 'refresh_token_required' });
  }
  
  // Validate refresh token
  const result = await db.query(
    'SELECT device_id FROM refresh_tokens WHERE token = $1 AND is_revoked = FALSE AND expires_at > NOW()',
    [refresh_token]
  );
  
  if (result.rows.length === 0) {
    return res.status(401).json({ error: 'invalid_refresh_token' });
  }
  
  const deviceId = result.rows[0].device_id;
  
  // Get device info
  const device = await db.query('SELECT room_id FROM devices WHERE id = $1', [deviceId]);
  
  // Generate new access token
  const newAccessToken = jwt.sign(
    { boardId: deviceId, roomId: device.rows[0].room_id, type: 'access' },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
  );
  
  res.json({
    access_token: newAccessToken,
    expires_in_ms: 900000,
    token_type: 'Bearer'
  });
});
```

### Step 5: Update Authentication Middleware

**OLD Middleware (DELETE):**
```javascript
const mac = req.headers['x-board-mac'];
if (!mac) return res.status(401).send('Missing MAC');
// ... validate MAC
```

**NEW Middleware (IMPLEMENT):**
```javascript
const authenticate = async (req, res, next) => {
  // Try JWT first
  const authHeader = req.headers['authorization'];
  if (authHeader) {
    const token = authHeader.split(' ')[1];
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      req.boardId = decoded.boardId;
      req.roomId = decoded.roomId;
      return next();
    } catch (err) {
      // JWT invalid, try API key next
    }
  }
  
  // Fallback to API key
  const apiKey = req.headers['x-api-key'];
  if (apiKey) {
    const result = await db.query(
      'SELECT id, room_id FROM devices WHERE api_key = $1 AND is_active = TRUE',
      [apiKey]
    );
    if (result.rows.length > 0) {
      req.boardId = result.rows[0].id;
      req.roomId = result.rows[0].room_id;
      return next();
    }
  }
  
  return res.status(401).json({ error: 'unauthorized' });
};

// Use in routes
app.get('/api/v1/board/sync-context', authenticate, (req, res) => {
  // req.boardId and req.roomId are set
  // ...
});
```

---

## 2. Database Changes

### Minimal Schema

```sql
-- Add to existing devices table (if exists)
ALTER TABLE devices ADD COLUMN IF NOT EXISTS api_key VARCHAR(128);

-- New table for refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id SERIAL PRIMARY KEY,
  device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
  token VARCHAR(64) UNIQUE NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  is_revoked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Generate API keys for existing devices
UPDATE devices 
SET api_key = 'bk_live_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
WHERE api_key IS NULL;
```

---

## 3. Test It

```bash
# 1. Register device (get tokens)
curl -X POST https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/register/verify-otp \
  -H "Content-Type: application/json" \
  -d '{
    "otp": "123456",
    "classroom_id": "CSE-45",
    "hardware_fingerprint": "WIN_UUID_test",
    "device_name": "Test Board"
  }'

# ✅ Should return: api_key, access_token, refresh_token

# 2. Use access token
curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "Authorization: Bearer <access_token>"

# ✅ Should return: 200 OK with schedule data

# 3. Refresh token
curl -X POST https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "<refresh_token>"}'

# ✅ Should return: new access_token

# 4. Test MAC spoofing (should fail)
curl https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/sync-context \
  -H "X-Board-MAC: 00:11:22:33:44:55"

# ✅ Should return: 401 Unauthorized
```

---

## 4. Timeline

| Task | Estimated Time |
|------|----------------|
| Install JWT library | 5 min |
| Generate JWT secret | 2 min |
| Update registration endpoint | 30 min |
| Create refresh endpoint | 30 min |
| Update middleware | 45 min |
| Database migration | 15 min |
| Testing | 30 min |
| **TOTAL** | **~2.5 hours** |

---

## 5. Frontend Compatibility

✅ Frontend v5.4 is **already deployed** with:
- Secure token storage
- JWT authentication
- Auto-refresh logic
- MAC address removed from auth

⚠️ **Frontend WILL FAIL** until backend implements tokens!

---

## 6. Questions?

**Check full documentation:** `BACKEND_API_SECURITY_v5.4.md`

**Frontend code reference:**
- `lib/services/api_service.dart` - How frontend sends tokens
- `lib/services/secure_storage_service.dart` - How frontend stores tokens
- `lib/services/device_service.dart` - How frontend uses tokens

**Contact:** [your-email@intelliattend.com]

---

**Status:** Ready for Implementation 🚀  
**Impact:** CRITICAL - Frontend cannot authenticate without these changes!
