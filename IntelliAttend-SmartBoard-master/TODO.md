# SmartBoard — Pending Work & Considerations

## Completed (This Release)

- [x] **TokenManager singleton** — unified token lifecycle (cache → refresh → hard re-auth)
- [x] **AuthInterceptor 401 replay** — transparent recovery with isolated Dio instance
- [x] **ApiService `_authHeaders()`** — wraps TokenManager for http.Client stack
- [x] **HeartbeatService proactive refresh** — force-refresh every 3rd beat (~15 min)
- [x] **Structured auth exceptions** — `NoCredentialsException`, `InvalidCredentialsException`
- [x] **Registration flow** — admin login + OTP + hardware binding verified on IASB-4208
- [x] **Unit tests** — 7/7 passing (cache, dedup, force-refresh, fallback, reset)
- [x] **Release build** — `flutter build windows --release` (15.5 MB)
- [x] **Auto-launch** — registered at `HKCU\...\Run` pointing to release exe

## Pending Work

### Medium Priority

- [ ] **Bundle `.env` with the release binary**
  The app crashes at startup if `.env` is missing. Current workaround is manual copy.
  Options: embed `FIREBASE_API_KEY` at build time via `--dart-define`, or bundle `.env` in the installer.

- [ ] **Set `SSL_PIN_FINGERPRINT` in `.env` for production**
  App logs `⚠️ SSL_PIN_FINGERPRINT not set`. Works without it, but production boards should pin to prevent MITM.
  ```
  SSL_PIN_FINGERPRINT=sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  ```

- [ ] **Monitor DPAPI file-lock contention on boot**
  Observed `flutter_secure_storage.dat` locked by concurrent processes (`errno = 32`).
  The retry loop (3 attempts) handles it, but if it becomes frequent, consider a mutex or delayed initialization.

### Low Priority

- [ ] **Tune WebSocket reconnection behavior**
  Logs show rapid `[WS] Connection closed / Reconnecting in 1s` cycles.
  Not blocking (recovers), but excessive chatter may indicate a config mismatch. Worth investigating if real-time attendance updates are affected.

- [ ] **Review startup watchdog timeout (45s)**
  `[Startup] Watchdog fired — startup not complete after 45s. Releasing kiosk constraints.`
  On slow hardware or cold boot, kiosk hardening is briefly released. Increase timeout or suppress if false alarms are observed.

- [ ] **Clean up old Isar migration path**
  The code migrates from `Documents\intelliattend_smartboard\` to `%APPDATA%\com.example\...\`.
  If a stale old-path database exists, a future factory reset could restore it. Document or remove the migration after N releases.

### Icebox

- [ ] **Board credential provisioning without touchscreen**
  Currently requires admin login + OTP per board via touchscreen UI.
  Future: pre-provision `board_email`/`board_password` via config file or QR code scanned at deployment.

- [ ] **Automated deployment pipeline**
  Manual ZIP → copy → extract → run flow. Consider MSI installer or Windows update mechanism.
