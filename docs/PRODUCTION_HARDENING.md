# 🔴 Production Hardening Checklist
## IntelliAttend Campus Geospatial System - Pre-Deployment

**Target:** CI Block Room 4114 (Your Classroom) Pilot  
**Timeline:** 2-3 days for full hardening  
**Status:** ⚠️ NOT PRODUCTION READY - Complete all mandatory items first

---

## ✅ Phase 1: Database Migration (MANDATORY)

### 1.1 Pre-Migration Verification

- [ ] **Backup current database**
  ```bash
  cd /Users/balaseetharamanjaneyulu/Dev/IntelliAttend/backend
  python -c "from app.core.firebase import initialize_firebase, db; initialize_firebase(); import json; docs = db.collection('classrooms').stream(); data = {d.id: d.to_dict() for d in docs}; open('manual_backup.json', 'w').write(json.dumps(data, default=str))"
  ```
  - ✅ Verify `manual_backup.json` created
  - ✅ Check file size > 0 bytes

- [ ] **Test migration in dry-run mode**
  ```bash
  python scripts/migrate_to_hierarchical_model.py --dry-run
  ```
  - ✅ Verify "DRY RUN COMPLETE" message
  - ✅ Check 13 classrooms would be updated
  - ✅ No error messages

### 1.2 Execute Migration

- [ ] **Run migration**
  ```bash
  python scripts/migrate_to_hierarchical_model.py --execute
  ```
  - ✅ Wait for "MIGRATION COMPLETE!" message
  - ✅ Check backups created in `./backups/` directory
  - ✅ Verify no errors

- [ ] **Verify migration results in Firestore Console**
  - [ ] `campuses/mrcet_main` exists with polygon boundary
  - [ ] `buildings/building_ci_block` exists
  - [ ] `floors/floor_ci_ground` exists
  - [ ] `floors/floor_ci_first` exists
  - [ ] `classrooms/room_4114` has:
    - `campus_id: "mrcet_main"`
    - `building_id: "building_ci_block"`
    - `floor_id: "floor_ci_first"`

---

## 🚶 Phase 2: Infrastructure Survey (MANDATORY)

### 2.1 Prepare Survey Tools

- [ ] **Install Wi-Fi analyzer app on smartphone**
  - iOS: "WiFi Explorer Lite" (Free)
  - Android: "WiFi Analyzer" by farproc (Free)

- [ ] **Create survey spreadsheet**
  ```
  Room | SSID | BSSID | RSSI (dBm) | Notes
  -----|------|-------|------------|-------
  4114 | ?    | ?     | ?          | Your classroom
  4113 | ?    | ?     | ?          |
  4112 | ?    | ?     | ?          |
  ...
  ```

### 2.2 Walk CI Block First Floor

**For EACH classroom (4101, 4102, 4106, 4108, 4109, 4112, 4113, 4114):**

- [ ] **Enter room**
- [ ] **Open Wi-Fi analyzer**
- [ ] **Record top 3 strongest networks**:
  - SSID (network name)
  - BSSID (MAC address like `AA:BB:CC:DD:EE:FF`)
  - RSSI strength (e.g., -45 dBm = strong, -75 dBm = weak)
- [ ] **Stand in center of room for 30 seconds**
- [ ] **Note if signal fluctuates**

### 2.3 Identify Optimal APs

- [ ] **For room 4114 specifically**:
  - [ ] Which AP has strongest signal? → This is your primary AP
  - [ ] Does signal stay > -70 dBm consistently?
  - [ ] Does same BSSID appear in neighbor rooms? (If yes, might need BLE beacons)

**Decision Point:**
- ✅ If each room has unique strong AP → Wi-Fi validation will work well
- ⚠️ If same AP covers multiple rooms → MUST deploy BLE beacons

---

## 📡 Phase 3: Register Infrastructure (MANDATORY)

### 3.1 Register Room 4114 Wi-Fi AP

Create temporary registration script:

```bash
cd /Users/balaseetharamanjaneyulu/Dev/IntelliAttend/backend
nano register_room4114_wifi.py
```

**File contents:**
```python
import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.core.firebase import initialize_firebase
import firebase_admin
from firebase_admin import firestore

if not firebase_admin._apps:
    initialize_firebase()

db = firestore.client()

# REPLACE WITH ACTUAL VALUES FROM SURVEY
wifi_data = {
    "wifi_id": "wifi_room4114_primary",
    "display_name": "College Wi-Fi - Room 4114 Primary",
    "ssid": "COLLEGE_WIFI",  # ← REPLACE with actual SSID
    "bssid": "AA:BB:CC:DD:EE:FF",  # ← REPLACE with actual BSSID from survey
    "band": "5GHz",  # or "2.4GHz" depending on survey
    "room_id": "room_4114",
    "floor_id": "floor_ci_first",
    "building_id": "building_ci_block",
    "campus_id": "mrcet_main",
    "rssi_profile": {
        "min": -80,  # Will tune with calibration
        "max": -40
    },
    "status": "ACTIVE",
    "created_by": "manual_setup",
    "created_at": firestore.SERVER_TIMESTAMP,
    "updated_at": firestore.SERVER_TIMESTAMP
}

db.collection("infrastructure_wifi").document(wifi_data["wifi_id"]).set(wifi_data)
print(f"✅ Registered Wi-Fi AP: {wifi_data['bssid']} for room 4114")
```

- [ ] **Update SSID, BSSID, band** with survey values
- [ ] **Run:** `python register_room4114_wifi.py`
- [ ] **Verify in Firestore:** `infrastructure_wifi/wifi_room4114_primary` exists

### 3.2 (Optional) Register BLE Beacon

**If needed based on survey results:**

- [ ] Purchase iBeacon (e.g., Estimote, $25)
- [ ] Configure beacon UUID via manufacturer app
- [ ] Place beacon in room 4114 (high corner, away from metal)
- [ ] Register in database (similar script)

---

## 🔬 Phase 4: Enable Calibration Mode (MANDATORY)

### 4.1 Update Room 4114 to Calibration Mode

```bash
cd /Users/balaseetharamanjaneyulu/Dev/IntelliAttend/backend
python -c "
from app.core.firebase import initialize_firebase, db
from firebase_admin import firestore
initialize_firebase()
db.collection('classrooms').document('room_4114').update({
    'calibration_mode': True,
    'updated_at': firestore.SERVER_TIMESTAMP
})
print('✅ Calibration mode enabled for room 4114')
"
```

- [ ] **Verify in Firestore:** `classrooms/room_4114/calibration_mode = true`

### 4.2 Collect Real Signal Data

**During next 3-5 attendance sessions in room 4114:**

- [ ] **Ask 5-10 students to mark attendance normally**
- [ ] **Monitor backend logs** for actual RSSI values
- [ ] **Record in spreadsheet:**
  ```
  Student | GPS Accuracy | Wi-Fi RSSI | BLE RSSI | Status
  --------|--------------|------------|----------|--------
  Student1| 15m          | -65 dBm    | -72 dBm  | Accepted
  Student2| 48m          | -58 dBm    | N/A      | Accepted
  Student3| 12m          | -71 dBm    | -68 dBm  | Accepted
  ```

### 4.3 Analyze Calibration Data

- [ ] **Find minimum RSSI observed** (e.g., weakest signal from valid position: -75 dBm)
- [ ] **Set threshold 5-10 dBm lower** (e.g., -80 dBm minimum)
- [ ] **Update infrastructure_wifi document:**
  ```python
  db.collection("infrastructure_wifi").document("wifi_room4114_primary").update({
      "rssi_profile.min": -80  # Based on calibration data
  })
  ```

### 4.4 Disable Calibration Mode

- [ ] **After collecting sufficient data (3-5 sessions):**
  ```bash
  python -c "
  from app.core.firebase import initialize_firebase, db
  from firebase_admin import firestore
  initialize_firebase()
  db.collection('classrooms').document('room_4114').update({
      'calibration_mode': False,
      'updated_at': firestore.SERVER_TIMESTAMP
  })
  print('✅ Calibration mode disabled - system now enforcing thresholds')
  "
  ```

---

## 🔧 Phase 5: Update Attendance Service (MANDATORY)

### 5.1 Make Trust Engine Async-Compatible

- [ ] **Edit:** `/Users/balaseetharamanjaneyulu/Dev/IntelliAttend/backend/app/services/attendance_service.py`

- [ ] **Find the line that calls** `TrustEngine.evaluate_trust()`

- [ ] **Change from:**
  ```python
  trust_result = TrustEngine.evaluate_trust(qr_valid, proximity_data, expected_context)
  ```

- [ ] **Change to:**
  ```python
  trust_result = await TrustEngine.evaluate_trust(qr_valid, proximity_data, expected_context)
  ```

- [ ] **Ensure the parent function is** `async def`

- [ ] **Add `room_id` to expected_context:**
  ```python
  expected_context = {
      "room_id": session_data.get("roomId") or session_data.get("classroom_id"),  # Add this
      "latitude": ...,
      "longitude": ...,
      # ... rest of context
  }
  ```

### 5.2 Test Backend with Postman/curl

- [ ] **Restart backend:**
  ```bash
  cd /Users/balaseetharamanjaneyulu/Dev/IntelliAttend/backend
  python main.py
  ```

- [ ] **Test attendance endpoint** with mock data including `room_id`

- [ ] **Verify response includes** `location_validation` in trust breakdown

---

## 🧪 Phase 6: Pilot Testing (CRITICAL)

### 6.1 Test Scenario 1: Valid Student in Room 4114

**Setup:**
- Student physically in room 4114
- Connected to registered Wi-Fi
- GPS enabled

**Expected Result:**
- ✅ Campus validation: PASS
- ✅ Building validation: PASS  
- ✅ Wi-Fi validation: PASS
- ✅ Attendance: MARKED
- ✅ Trust score: 70-100

**Test:**
- [ ] Mark attendance via mobile app
- [ ] Check backend logs for validation layers
- [ ] Verify attendance marked in Firestore

### 6.2 Test Scenario 2: Student Outside Campus

**Setup:**
- Student at home
- Mock GPS inside room (if possible via developer options)
- NOT connected to college Wi-Fi

**Expected Result:**
- ❌ Campus validation: FAIL (if GPS is real location)
- ❌ Wi-Fi validation: FAIL (unregistered BSSID)
- ❌ Attendance: REJECTED
- 🚨 Flag: `UNREGISTERED_WIFI` or `OUTSIDE_CAMPUS_BOUNDARY`

**Test:**
- [ ] Attempt attendance from home
- [ ] Verify rejection
- [ ] Check `reject_reason` in response

### 6.3 Test Scenario 3: Student in Wrong Room

**Setup:**
- Student in room 4113 (neighbor)
- Session active in room 4114
- Connected to same college Wi-Fi

**Expected Result:**
- Depends on Wi-Fi coverage:
  - If rooms have different APs: ❌ Wi-Fi FAIL → REJECTED
  - If same AP covers both: ⚠️ May pass GPS check → Need BLE beacons

**Test:**
- [ ] Stand in neighbor room
- [ ] Attempt attendance for room 4114 session
- [ ] Check if system correctly rejects or needs BLE enhancement

---

## 🚀 Phase 7: Production Deployment Checklist

### 7.1 Pre-Launch Verification

- [ ] ✅ All Phase 1-6 items complete
- [ ] ✅ Migration executed successfully
- [ ] ✅ At least room 4114 infrastructure registered
- [ ] ✅ Calibration data collected and thresholds set
- [ ] ✅ Attendance service updated to async
- [ ] ✅ Test scenarios 1 & 2 passed

### 7.2 Rollback Plan

**If issues occur during pilot:**

```bash
# Restore classrooms from backup
python scripts/migrate_to_hierarchical_model.py --rollback ./backups/classrooms_backup_YYYYMMDD_HHMMSS.json

# Disable new validation temporarily
python -c "
from app.core.firebase import initialize_firebase, db
initialize_firebase()
db.collection('classrooms').document('room_4114').update({
    'use_legacy_validation': True  # Add this flag to skip hierarchical validation
})
"
```

### 7.3 Monitoring (First Week)

- [ ] **Daily:** Check `audit_logs` collection for validation failures
- [ ] **Daily:** Review trust score distribution (should be 70-100 for valid students)
- [ ] **Daily:** Monitor `reject_reason` frequencies:
  - High `UNREGISTERED_WIFI` → Infrastructure survey incomplete
  - High `OUTSIDE_CAMPUS_BOUNDARY` → Campus polygon incorrect
  - High `GPS_OUTSIDE_BUILDING` → Building boundary incorrect

### 7.4 Success Criteria

**After 1 week, system is production-ready if:**
- ✅ 95%+ of valid students marked successfully
- ✅ 100% of out-of-room attempts rejected
- ✅ No false rejections (faculty confirms all present students marked)
- ✅ Average trust score > 80 for valid students

---

## 📊 Quick Reference Commands

### Check Migration Status
```bash
python -c "from app.core.firebase import initialize_firebase, db; initialize_firebase(); doc = db.collection('classrooms').document('room_4114').get(); print('Has hierarchy:', 'campus_id' in doc.to_dict())"
```

### Check Registered Infrastructure
```bash
python -c "from app.core.firebase import initialize_firebase, db; initialize_firebase(); count = sum(1 for _ in db.collection('infrastructure_wifi').stream()); print(f'Registered Wi-Fi APs: {count}')"
```

### Check Calibration Mode
```bash
python -c "from app.core.firebase import initialize_firebase, db; initialize_firebase(); doc = db.collection('classrooms').document('room_4114').get(); print('Calibration mode:', doc.to_dict().get('calibration_mode', False))"
```

### View Recent Audit Logs
```bash
python -c "from app.core.firebase import initialize_firebase, db; initialize_firebase(); logs = db.collection('audit_logs').order_by('timestamp', direction='DESCENDING').limit(5).stream(); [print(f'{log.to_dict()}') for log in logs]"
```

---

## ⚠️ STOP - Do NOT Deploy Until:

- [ ] ✅ Migration executed (not just dry-run)
- [ ] ✅ Room 4114 Wi-Fi registered with REAL BSSID
- [ ] ✅ Calibration mode enabled & data collected
- [ ] ✅ Trust Engine made async in attendance_service.py
- [ ] ✅ Test scenario 1 & 2 passed

**Estimated Time:** 2-3 days (1 day setup, 2-3 days calibration data collection)

---

## 🆘 Troubleshooting

### Issue: "UNREGISTERED_WIFI" on every scan
**Cause:** BSSID from survey doesn't match actual BSSID from mobile app  
**Fix:** 
1. Check exact BSSID from student's phone during scan (add logging)
2. Update `infrastructure_wifi` document with correct BSSID

### Issue: "OUTSIDE_CAMPUS_BOUNDARY" but student is on campus
**Cause:** Campus polygon coordinates incorrect  
**Fix:**
1. Use Google Maps to get precise boundary coordinates
2. Update `campuses/mrcet_main/boundary_polygon`

### Issue: Trust Engine import error
**Cause:** Circular dependency or missing async  
**Fix:** Verify all imports at top of `attendance_service.py`

---

**Last Updated:** 2026-01-15  
**Next Review:** After pilot completion (1 week from deployment)
