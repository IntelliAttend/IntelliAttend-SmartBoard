# Disaster Recovery Runbook

## 1. SmartBoard App Crash on Startup
**Symptoms:** App crashes immediately, blank screen, or stuck on boot screen.  
**Recovery:**
1. Check logs: `%APPDATA%\IntelliAttend\logs\app.log` (Windows) or `~/Library/Logs/IntelliAttend/` (macOS)
2. Wipe local Isar vault: delete `intelliattend_vault_v2.isar` from `getApplicationSupportDirectory()`
3. Reboot the device
4. If persists, reinstall via MSI

## 2. Firebase Outage
**Symptoms:** No timetable sync, attendance upload fails, heartbeat fails.  
**Recovery:**
- SmartBoard operates in degraded offline mode automatically.
- Queued scans are stored in local Isar vault and synced when Firebase recovers.
- No manual action required.

## 3. Backend API Down
**Symptoms:** `POST /api/v1/board/register/request-otp` returns 5xx or timeout.  
**Recovery:**
1. Check backend health: `GET /api/v1/board/ready`
2. Restart backend: `systemctl restart intelliattend-backend` (Linux) or restart the uvicorn process
3. Check Firestore connectivity on backend host

## 4. Certificate Expiry / SSL Failure
**Symptoms:** `SSL_PIN_FINGERPRINT` mismatch, all API calls fail.  
**Recovery:**
1. Update `SSL_PIN_FINGERPRINT` in `.env` with new certificate SHA-256
2. Rebuild and redeploy the MSI
3. Emergency: set `SSL_PIN_FINGERPRINT` to empty to disable pinning temporarily

## 5. Version Rollback
**Symptoms:** New release introduces regression.  
**Recovery:**
1. Locate previous signed MSI in CI artifacts or releases
2. Uninstall current version via Windows Settings > Apps
3. Install previous MSI
4. Verify heartbeat on IT dashboard within 5 minutes
