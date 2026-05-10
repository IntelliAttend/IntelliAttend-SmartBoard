param(
    [switch]$Clean,
    [string]$ProjectId = "",
    [string]$ClassroomId = "room_4208",
    [string]$BoardId = "IASB-4208"
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
$serviceAccountKey = "$rootDir\backend\python\serviceAccountKey.json"

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Firestore Seed Data Tool v1.0                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
if (-not (Test-Path $serviceAccountKey)) {
    Write-Host "  ✗ serviceAccountKey.json not found at:" -ForegroundColor Red
    Write-Host "    $serviceAccountKey" -ForegroundColor Red
    Write-Host "  ── To proceed ──" -ForegroundColor Yellow
    Write-Host "  1. Go to Firebase Console → Project Settings → Service Accounts" -ForegroundColor Yellow
    Write-Host "  2. Generate a new private key" -ForegroundColor Yellow
    Write-Host "  3. Save as backend\python\serviceAccountKey.json" -ForegroundColor Yellow
    Write-Host "  4. Re-run this script" -ForegroundColor Yellow
    exit 1
}

# Run Python seed script
$pythonScript = @"
import json, os, sys
from datetime import datetime, timedelta, timezone

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("ERROR: firebase-admin not installed. Run: pip install firebase-admin")
    sys.exit(1)

SERVICE_ACCOUNT = r"$serviceAccountKey"
PROJECT_ID = "$ProjectId" or None
CLEAN = $($Clean -as [bool] -replace 'True','True' -replace 'False','False')
CLASSROOM = "$ClassroomId"
BOARD_ID = "$BoardId"

cred = credentials.Certificate(SERVICE_ACCOUNT)
if PROJECT_ID:
    firebase_admin.initialize_app(cred, {"projectId": PROJECT_ID})
else:
    firebase_admin.initialize_app(cred)
db = firestore.client()
print("✓ Firebase initialized")

# ── Optionally clean ──
if CLEAN:
    collections = ["timetable_slots", "Sessions", "ActiveSessions", "smart_boards", "board_heartbeats"]
    for col_name in collections:
        docs = db.collection(col_name).list_documents()
        deleted = 0
        for doc in docs:
            # Delete subcollections too
            for sub in doc.collections():
                for subdoc in sub.list_documents():
                    subdoc.delete()
            doc.delete()
            deleted += 1
        print(f"  Cleaned {col_name}: {deleted} docs deleted")
    print("✓ Clean complete")

# ── Seed timetable slots ──
today = datetime.now(timezone.utc)
weekdays = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
periods = [
    ("08:00","09:00"), ("09:00","10:00"), ("10:00","11:00"),
    ("11:00","12:00"), ("13:00","14:00"), ("14:00","15:00"),
    ("15:00","16:00"), ("16:00","17:00")
]
subjects = [
    "Data Structures", "Algorithms", "Database Systems",
    "Computer Networks", "Operating Systems", "AI & ML",
    "Software Engineering", "Web Development"
]

slot_count = 0
for day_offset in range(7):
    day_name = weekdays[day_offset]
    for period_idx, (start, end) in enumerate(periods):
        slot_id = f"{CLASSROOM}_{day_name[:3].lower()}_{period_idx+1}"
        slot_data = {
            "classroom_id": CLASSROOM,
            "day_of_week": day_name,
            "start_time": start,
            "end_time": end,
            "subject_name": subjects[period_idx % len(subjects)],
            "faculty_name": f"Prof. {subjects[period_idx % len(subjects)].split()[0]}",
            "section": "CSE-A",
            "roster_count": 60 + period_idx * 5,
            "smart_board_id": BOARD_ID,
            "is_active": True
        }
        db.collection("timetable_slots").document(slot_id).set(slot_data)
        slot_count += 1

print(f"✓ Seeded {slot_count} timetable slots for classroom {CLASSROOM}")

# ── Register smart board ──
board_data = {
    "device_id": BOARD_ID,
    "classroom_id": CLASSROOM,
    "room_name": f"Room {CLASSROOM.split('_')[1]}",
    "building": "Main Building",
    "department": "Computer Science",
    "capacity": 60,
    "is_registered": True,
    "firmware_version": "v5.4",
    "last_seen": firestore.SERVER_TIMESTAMP,
    "health": {"status": "online"}
}
db.collection("smart_boards").document(BOARD_ID).set(board_data, merge=True)
print(f"✓ Registered smart board: {BOARD_ID}")

print("╔══════════════════════════════════════════════════╗")
print("║  SEED COMPLETE                                   ║")
print(f"║  Classroom: {CLASSROOM}                             ║")
print(f"║  Board ID:  {BOARD_ID}                              ║")
print(f"║  Slots:     {slot_count}                                 ║")
print("╚══════════════════════════════════════════════════╝")
"@

$pythonFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.py'
Set-Content -Path $pythonFile -Value $pythonScript

try {
    & python $pythonFile 2>&1
} finally {
    Remove-Item $pythonFile -Force -ErrorAction SilentlyContinue
}
