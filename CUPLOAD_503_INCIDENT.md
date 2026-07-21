# CI/CD Upload 503 Incident Report — For Server Team

**Date:** 2026-07-21
**Severity:** Blocking new releases
**API Endpoint:** `https://api.intelliattend.app/api/v1/board/ci-upload`

---

## 1. Summary

GitHub Actions CI builds a new MSI installer for IntelliAttend SmartBoard, then uploads it to the production server at `api.intelliattend.app`. The upload step consistently fails with **HTTP 503**. The MSI is built successfully and published to GitHub Releases, but the server never receives the release manifest, so devices cannot discover the new version.

---

## 2. What Should Happen

1. CI pushes code to `school-main`
2. CI builds the Flutter Windows app → produces a 19MB `.msi` file
3. CI creates a GitHub Release (`v5.5.0.12`) with the MSI attached
4. CI sends the MSI to `POST https://api.intelliattend.app/api/v1/board/ci-upload` with:
   - Header: `X-Deploy-Key: <value must match server DEPLOY_KEY>`
   - Form fields: `version`, `release_notes`, `commit_hash`, `force`, `rollout_percentage`, `file`
5. Server stores the release manifest in the database
6. Connected devices receive the update via heartbeat polling

**Step 4 is failing with 503.** Steps 1-3 succeed.

---

## 3. The Error

### CI Output
```
curl -f -X POST "https://api.intelliattend.app/api/v1/board/ci-upload" \
  -H "X-Deploy-Key: ***" \
  -F "version=5.5.0+12" \
  -F "release_notes=Auto-deploy from commit e0cfe74..." \
  -F "commit_hash=e0cfe74dd3613fcf08bfe82ca6ec04e8a4f7dba7" \
  -F "force=true" \
  -F "rollout_percentage=100" \
  -F "file=@intelliattend_smartboard-5.5.0.12.msi"

# Result:
curl: (22) The requested URL returned error: 503
# Exit code: 22
```

### Server-Side Code (backend/python/main.py, lines 1374-1394)
```python
DEPLOY_KEY = os.environ.get("DEPLOY_KEY", "")   # line 1374

@app.post("/api/v1/board/ci-upload")
async def ci_upload(
    version: str = "",
    file: Optional[str] = None,
    x_deploy_key: str = Header(default=""),
    ...
):
    if not DEPLOY_KEY:                                          # line 1391
        raise HTTPException(
            status_code=503,
            detail="CI upload not configured (DEPLOY_KEY not set)"   # line 1392
        )
    if x_deploy_key != DEPLOY_KEY:                             # line 1393
        raise HTTPException(status_code=401, detail="Invalid deploy key")
```

The **only** path that returns 503 is line 1392: the server's `DEPLOY_KEY` environment variable is empty/not set.

---

## 4. What I Tested (Evidence)

### Test A — No deploy key header, no file body
```
POST /api/v1/board/ci-upload
(no X-Deploy-Key header)
Response: 422 {"detail":[{"loc":["body","file"],"msg":"Field required"}]}
```
**Interpretation:** The endpoint is live and processing requests. It skips past the DEPLOY_KEY check (returns 422 for missing `file` instead of 503 or 401). This means the server code IS deployed and `DEPLOY_KEY` may actually be set now.

### Test B — Wrong deploy key, no file
```
POST /api/v1/board/ci-upload
Header: X-Deploy-Key: test
Response: 422 {"detail":[{"loc":["body","file"],"msg":"Field required"}]}
```
**Same as A** — validation fails on missing file before hitting the auth check.

### Test C — Wrong deploy key WITH 19MB MSI file
```
POST /api/v1/board/ci-upload
Header: X-Deploy-Key: test
Body: multipart/form-data with intelliattend_smartboard-5.5.0.12.msi (19MB)
Response: 401 {"error_code":"Invalid deploy key","message":"Invalid deploy key"}
```
**Critical finding:** The server processed the full 19MB upload and returned **401** (not 503). This proves:
1. The server CAN handle the 19MB file upload without timeout
2. `DEPLOY_KEY` IS set on the server (wrong key gives 401, not 503)
3. The `ci-upload` endpoint is fully functional

---

## 5. The Contradiction

| Scenario | Expected | Actual (CI) | Actual (Local Test) |
|---|---|---|---|
| DEPLOY_KEY not set on server | 503 | **503** | N/A |
| DEPLOY_KEY set, wrong key | 401 | N/A | **401** |
| DEPLOY_KEY set, correct key | 200 | N/A | N/A |

The CI gets **503** (server thinks DEPLOY_KEY is not set), but my local test with the same 19MB file gets **401** (server proves DEPLOY_KEY IS set).

**Possible explanations (in order of likelihood):**

1. **GitHub secret `DEPLOY_KEY` is not set or is empty** — In GitHub Actions, `${{ secrets.DEPLOY_KEY }}` evaluates to `""` if not configured. The CI log masks it as `***` even for empty values in some cases. If the header sends an empty key AND the server has DEPLOY_KEY set, it should return 401 (not 503). However, there could be a race condition during server redeployment where the endpoint is temporarily unavailable.

2. **Server was redeploying during the CI run** — The push to `school-main` triggers both the CI build AND the server auto-deploy. If the server restarts while the CI is uploading, it could return 503 during the deployment window. My local test ran after the server had fully restarted.

3. **Cloudflare is returning 503** — The server is behind Cloudflare. A 19MB multipart upload could hit a Cloudflare limit or timeout during peak load, though my local test proved this works under normal conditions.

---

## 6. Action Items for Server Team

### Immediate Fix (do these first)

1. **Verify `DEPLOY_KEY` is set in the server environment:**
   - Check the hosting dashboard (wherever `api.intelliattend.app` is deployed)
   - Look for environment variables / secrets configuration
   - Confirm `DEPLOY_KEY` has a non-empty value

2. **Verify the value matches the GitHub secret:**
   - Go to GitHub repo: `IntelliAttend/IntelliAttend-SmartBoard` → Settings → Secrets and variables → Actions
   - Check the `DEPLOY_KEY` secret value
   - Ensure server env var `DEPLOY_KEY` = GitHub secret `DEPLOY_KEY`

3. **After confirming/re-setting DEPLOY_KEY, re-run the failed CI job:**
   ```bash
   gh run rerun 29796867038 --repo IntelliAttend/IntelliAttend-SmartBoard --failed
   ```

### Verify the Upload Works

4. **Test the endpoint manually after fixing:**
   ```bash
   # Replace YOUR_DEPLOY_KEY with the actual value
   curl -X POST "https://api.intelliattend.app/api/v1/board/ci-upload" \
     -H "X-Deploy-Key: YOUR_DEPLOY_KEY" \
     -F "version=5.5.0.12" \
     -F "release_notes=test upload" \
     -F "commit_hash=e0cfe74" \
     -F "force=true" \
     -F "rollout_percentage=100" \
     -F "file=@path/to/intelliattend_smartboard-5.5.0.12.msi"
   ```
   Expected response: `{"status":"ok","version":"5.5.0+12"}`

5. **Verify the download endpoint serves the new version:**
   ```bash
   curl -I "https://api.intelliattend.app/api/v1/board/download/latest"
   ```
   The `content-disposition` header should show `intelliattend_smartboard-5.5.0.12.msi` (currently shows `5.5.0.11.msi`).

---

## 7. Current State

| Item | Status |
|---|---|
| MSI built successfully | **YES** — `intelliattend_smartboard-5.5.0.12.msi` (19MB) |
| GitHub Release created | **YES** — `v5.5.0.12` at https://github.com/IntelliAttend/IntelliAttend-SmartBoard/releases/tag/v5.5.0.12 |
| Upload to server | **FAILED** — 503 |
| Download endpoint | Serving old version `5.5.0.11.msi` (last modified Jul 19) |
| Devices will auto-update | **NO** — server manifest still points to `5.5.0.11` |

---

## 8. CI Workflow Reference

- **Workflow file:** `.github/workflows/auto-deploy.yml`
- **Trigger:** Push to `school-main`
- **Upload step:** Lines 236-256
- **Server URL:** Configured as GitHub Actions variable `SERVER_URL` = `https://api.intelliattend.app`
- **Auth header:** `X-Deploy-Key` sent from GitHub secret `DEPLOY_KEY`
- **CI Run ID:** `29796867038` (failed), re-run `88532426176` (also failed)

---

## 9. Contact

- **Repo:** IntelliAttend/IntelliAttend-SmartBoard
- **Branch:** school-main
- **Latest commit:** `e0cfe74` — `fix(installer): use WelcomeDlg from WixUI_Minimal and fix RadioButtonGroup syntax`
