IntelliAttend - Complete System Architecture & Registration Flow Documentation
🎯 Executive Summary
This document clarifies the complete user lifecycle from admin account creation through registration, login, and daily usage. It resolves confusion between teams about authentication, registration, and token management.
---
1. System Architecture Overview
1.1 Two-Factor Identity System
Layer	Purpose	Storage
Firebase Auth	Authentication (Who are you?)	Firebase Auth (Google-managed)
Firestore	Authorization & Profile (What can you do?)	Cloud Firestore (Our database)
1.2 Collection Structure (Canonical)
users/{email}              ← Auth metadata, device binding, is_registered flag
faculties/{email}          ← Faculty profile (name, department, subjects)
students/{email}           ← Student profile (roll_number, section, year)
1.3 Legacy Collections (Dual-Write During Migration)
faculty_profiles/{email}   ← Deprecated, being phased out
student_profiles/{email}   ← Deprecated, being phased out
faculty/{email}            ← Deprecated, explicitly denied in Firestore rules
---
2. Complete User Lifecycle
Phase 1: Admin Creates Account (Pre-Registration)
What Admin Does:
- Creates Firebase Auth account: auth.create_user(email=email, password=password)
- Creates Firestore document: users/{email} with is_registered: false
- Creates profile document: faculties/{email} or students/{email} with is_registered: false
- Shares credentials with user: Email + Password
Database State After Admin Setup:
Firebase Auth: ✅ Account exists (email + password)
users/{email}: ✅ Document exists, is_registered: false
faculties/{email}: ✅ Document exists, is_registered: false
Phase 2: User Opens App for First Time
What Happens:
Step 1: User opens app → Shows Login Screen
Step 2: User enters Email + Password (provided by admin)
Step 3: Firebase Auth validates → NOW we know who they are
Step 4: App calls FacultyService.load() using the email from Firebase
Step 5: Reads faculties/{email} from Firestore
Step 6: Checks is_registered field
        → If false: Redirect to Registration
        → If true: Go to Dashboard


The Key Point
We don't know who the user is until they authenticate with email/password first. Only after Firebase Auth succeeds do we:
1. Get the user's email from the Firebase token
2. Use that email to look up their profile in Firestore
3. Check if is_registered is true or false
4. Decide where to send them (Registration or Dashboard)
Visual Flow
┌─────────────────────┐
│  App Opens           │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Login Screen        │  ← User enters email + password
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Firebase Auth       │  ← Validates credentials
│  (Who are you?)      │  ← Returns email, uid
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Load Profile        │  ← Read faculties/{email} from Firestore
│  (Are you registered?)│ ← Check is_registered field
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
┌─────────┐ ┌──────────┐
│is_reg:  │ │is_reg:   │
│ false   │ │ true     │
└────┬────┘ └────┬─────┘
     │           │
     ▼           ▼
┌─────────┐ ┌──────────┐
│Register │ │Dashboard │
│ Screen  │ │          │
└─────────┘ └──────────┘
Summary
Question	Answer
Do we check registration before login?	No - Login happens first
How do we know who the user is?	Firebase Auth returns email after successful login
When do we check is_registered?	After Firebase Auth succeeds, during profile load
What if user is not registered?	Redirect to Registration Flow
What if user is registered?	Go to Dashboard 







Critical Point: User CAN log in (Firebase Auth succeeds), but CANNOT access dashboard until registration completes.
Phase 3: Registration Flow (OTP + Device Binding)
Step 1: Initiate (Email Verification)
User Action: Enters email → Taps "Send OTP"
App Action: POST /api/v1/Faculty/register/initiate
           Body: {"email": "fac03@mrcet.ac.in"}
Server Action: Sends 6-digit OTP to email
Response: {"status": "success", "id": "fac03@mrcet.ac.in", "debug_otp": "123456"}
Step 2: Verify OTP
User Action: Enters 6-digit OTP
App Action: POST /api/v1/Faculty/register/verify
           Body: {"email": "fac03@mrcet.ac.in", "otp": "123456"}
Server Action: Validates OTP, sets pin_verified_at on users/{email}
Response: {"status": "success", "message": "PIN verified."}
Step 3: Complete (Password + Device Binding)
FACULTY FLOW:
User Action: Sets password → Taps "Complete"
App Action: POST /api/v1/Faculty/register/complete
           Headers: Authorization: Bearer <Firebase-ID-Token>
           Body: {
             "email": "fac03@mrcet.ac.in",
             "password": "NewSecurePassword123!",
             "device_info": {
               "device_id": "...",
               "device_fingerprint": "...",
               "brand": "Google",
               "model": "Pixel 7",
               "is_rooted": false,
               ...
             }
           }
Server Action:
  1. Validates Firebase ID Token → Extracts UID, email
  2. Verifies token email matches registration email
  3. Creates/updates Firebase Auth account with new password
  4. Writes to Firestore (dual-write: faculties + faculty_profiles)
  5. Sets is_registered: true
Response: {
  "success": true,
  "message": "Registration complete. Device successfully bound.",
  "profile": {...},
  "is_registered": true
}
STUDENT FLOW:
User Action: Sets password → Taps "Complete"
App Action: POST /api/v1/Student/register/complete
           Body: {
             "email": "23n31a6645@mrcet.ac.in",
             "password": "NewSecurePassword123!",
             "device_info": {...}
           }
           (NO Bearer token header required for students)
Server Action:
  1. Checks pin_verified_at (set during OTP verify step)
  2. Creates/updates Firebase Auth account with new password
  3. Writes to Firestore (dual-write: students + student_profiles)
  4. Sets is_registered: true
Response: {
  "success": true,
  "message": "Registration complete. Device successfully bound.",
  "profile": {...},
  "is_registered": true
}
Phase 4: Post-Registration State
What App Does:
1. Receives profile from server response
2. Calls FacultyService.applyProfile(profileData) or StudentService.applyProfile(profileData)
3. applyProfile() does:
   - Sets isRegistered.value = true
   - Caches profile to Hive (local storage)
   - Triggers UI navigation to Dashboard
4. User is now on Dashboard
Database State After Registration:
Firebase Auth: ✅ Account exists (email + new password)
users/{email}: ✅ is_registered: true, device_id: "...", device_fingerprint: "..."
faculties/{email}: ✅ is_registered: true, device_id: "..."
Phase 5: Daily Usage (Login After Registration)
What Happens:
1. User opens app → Firebase Auth auto-restores session (if token not expired)
2. If expired: User logs in with Email + Password → Firebase Auth validates
3. App calls FacultyService.load():
   - Loads cached profile from Hive (instant UI)
   - Queries Firestore faculties/{email} to confirm is_registered: true
   - Sets up real-time listeners
4. User sees Dashboard immediately
---
3. Token Management (How Server Verifies Requests)
3.1 What Token is Used?
ALL API requests use Firebase ID Token as Bearer token:
Authorization: Bearer <Firebase-ID-Token>
3.2 How Token Works
┌─────────────────────────────────────────────────────────┐
│ Client Side                                             │
├─────────────────────────────────────────────────────────┤
│ 1. User logs in with email + password                   │
│ 2. Firebase Auth generates ID Token (JWT)               │
│ 3. Token contains: {uid, email, role, exp, jti}         │
│ 4. App attaches token to every API request              │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Server Side                                             │
├─────────────────────────────────────────────────────────┤
│ 1. Extracts Bearer token from Authorization header      │
│ 2. Calls firebase_auth.verify_id_token(token)           │
│ 3. Decodes token → gets uid, email                      │
│ 4. Looks up user in Firestore by firebase_uid or email  │
│ 5. Checks device_id matches request X-Device-ID header  │
│ 6. Returns UserProfile or 401 Unauthorized              │
└─────────────────────────────────────────────────────────┘
3.3 Token Lifecycle
Event	What Happens
Login	Firebase generates ID Token (expires in 1 hour)
Token Refresh	Firebase SDK auto-refreshes before expiry
Logout	Token discarded, Firebase session cleared
Device Change	New device → new token → device_id mismatch → 401
3.4 Headers Sent With Every Request
Authorization: Bearer <Firebase-ID-Token>    ← Identity proof
X-Device-ID: <unique-device-id>              ← Hardware binding
X-Device-Fingerprint: <fingerprint-hash>     ← Anti-spoofing
X-Device-Model: <phone-model>                ← Device metadata
X-App-Version: <app-version>                 ← Version tracking
---
4. Critical Differences: Faculty vs Students
Aspect	Faculty	Students
Pre-Registration	Admin creates account + shares credentials	Admin creates account + shares credentials
Login First?	Yes, Firebase Auth login happens before registration	Yes, Firebase Auth login happens before registration
Registration Gate	Firebase ID Token (Bearer header)	PIN verification (pin_verified_at flag)
Password	Set during registration (overrides admin password)	Set during registration (overrides admin password)
Device Binding	Required (device_id stored in Firestore)	Required (device_id stored in Firestore)
Post-Registration	FacultyService.applyProfile(profileData)	StudentService.applyProfile(profileData)
Canonical Collection	faculties/{email}	students/{email}
Attendance Flow	Starts sessions, marks students	Scans QR, marks own attendance
---
5. Mobile Team - Implementation Checklist
Faculty App
#	Check	Status
Authentication	 	 
1	Firebase Auth login with email + password	☐
2	After login, call FacultyService.load()	☐
3	Read faculties/{email} from Firestore	☐
4	Check is_registered flag	☐
5	If false → redirect to Registration	☐
Registration	 	 
6	Step 1: POST /api/v1/Faculty/register/initiate	☐
7	Step 2: POST /api/v1/Faculty/register/verify	☐
8	Step 3: POST /api/v1/Faculty/register/complete with Bearer token	☐
9	Bearer token = Firebase ID Token from current session	☐
10	Response contains profile dict	☐
Post-Registration	 	 
11	Call FacultyService.applyProfile(profileData)	☐
12	applyProfile() sets isRegistered.value = true	☐
13	Cache profile to Hive	☐
14	Navigate to Dashboard	☐
Daily Usage	 	 
15	Auto-login via Firebase Auth session restore	☐
16	Attach Bearer token to all API requests	☐
17	Attach X-Device-ID header	☐
18	Handle 401 → Force logout if hardware/device error	☐
Student App
#	Check	Status
Authentication	 	 
1	Firebase Auth login with email + password	☐
2	After login, call StudentService.load()	☐
3	Read students/{email} from Firestore	☐
4	Check is_registered flag	☐
5	If false → redirect to Registration	☐
Registration	 	 
6	Step 1: POST /api/v1/Student/register/initiate	☐
7	Step 2: POST /api/v1/Student/register/verify	☐
8	Step 3: POST /api/v1/Student/register/complete (no Bearer required)	☐
9	Response contains profile dict	☐
Post-Registration	 	 
10	Call StudentService.applyProfile(profileData)	☐
11	applyProfile() sets isRegistered.value = true	☐
12	Cache profile to Hive	☐
13	Navigate to Dashboard	☐
Daily Usage	 	 
14	Auto-login via Firebase Auth session restore	☐
15	Attach Bearer token to all API requests	☐
16	Attach X-Device-ID header	☐
17	Handle 401 → Force logout if hardware/device error	☐
---
## 6. Common Confusions Resolved
### ❌ "Do users need to register before they can log in?"
**Answer:** No. Users can log in immediately with admin-provided credentials. Registration is a separate step that happens after first login.
### ❌ "What's the difference between Login and Registration?"
**Answer:**
- **Login** = Firebase Auth verifies email + password → User is authenticated
- **Registration** = Device binding + profile completion → User is authorized to use the app
### ❌ "Why do faculty need a Bearer token for registration but students don't?"
**Answer:** Faculty registration uses Firebase ID Token as the verification gate instead of PIN. Students use PIN verification (set during Step 2). Both achieve the same goal: proving the user owns the email.
### ❌ "What happens if a user changes devices?"
**Answer:** Device ID changes → Server detects mismatch → Returns 401 → User must contact admin to reset device binding.
### ❌ "Do we need to save the token after registration?"
**Answer:** No. Firebase SDK manages tokens automatically. The app just calls `currentUser.getIdToken()` when needed - Firebase handles refresh.
### ❌ "What if the app is killed and reopened?"
**Answer:** Firebase Auth restores session automatically. App loads cached profile from Hive, then verifies with Firestore. User stays on Dashboard.
---
7. API Reference
Registration Endpoints
Endpoint	Method	Auth Required	Description
/api/v1/Faculty/register/initiate	POST	No	Send OTP to faculty email
/api/v1/Faculty/register/verify	POST	No	Verify OTP
/api/v1/Faculty/register/complete	POST	Bearer Token Required	Complete registration with device binding
/api/v1/Student/register/initiate	POST	No	Send OTP to student email
/api/v1/Student/register/verify	POST	No	Verify OTP
/api/v1/Student/register/complete	POST	No	Complete registration with device binding
Session Endpoints
Endpoint	Method	Auth Required	Description
/api/v1/faculty/start_session	POST	Bearer Token	Start attendance session, get OTP
/api/v1/faculty/generate_qr	POST	Bearer Token	Generate QR code after OTP verification
/api/v1/faculty/schedule	GET	Bearer Token	Get faculty schedule
Auth Endpoints
Endpoint	Method	Auth Required	Description
/api/v1/auth/login	POST	No	Login with email + password
/api/v1/auth/logout	POST	Bearer Token	Logout (audit only)
/api/v1/auth/login-or-onboard	POST	No	Unified login/onboarding
---
8. Database Schema Reference
users/{email}
Field	Type	Description
email	string	Canonical identifier
role	string	"faculty" or "student"
is_registered	boolean	True after device binding
firebase_uid	string	Firebase Auth UID
device_id	string	Bound device ID
device_fingerprint	string	Hardware fingerprint hash
account_status	string	"ACTIVE" or "BLOCKED"
pin_verified_at	timestamp	When OTP was verified
faculties/{email}
Field	Type	Description
email	string	Canonical identifier
name	string	Faculty name
department	string	Department name
designation	string	Job title
role	string	"faculty"
is_registered	boolean	True after device binding
subjects_assigned	list	Subject codes
students/{email}
Field	Type	Description
email	string	Canonical identifier
name	string	Student name
roll_number	string	University roll number
section_id	string	Section identifier
year	int	Academic year
role	string	"student"
is_registered	boolean	True after device binding
---
9. Testing Checklist
End-to-End Test: Faculty Registration
1. Admin creates account: fac03@mrcet.ac.in / SecurePassword123!
2. User opens app → Login Screen
3. User enters credentials → Firebase Auth succeeds
4. App reads faculties/fac03@mrcet.ac.in → is_registered: false
5. App redirects to Registration
6. User enters email → Receives OTP
7. User enters OTP → Verified
8. User sets password → Completes registration
9. Server returns profile → App calls applyProfile()
10. Dashboard loads → Schedule visible
11. User starts session → OTP generated
12. OTP entered on SmartBoard → QR displayed
13. Student scans QR → Attendance marked
End-to-End Test: Student Registration
1. Admin creates account: 23n31a6645@mrcet.ac.in / SecurePassword123!
2. User opens app → Login Screen
3. User enters credentials → Firebase Auth succeeds
4. App reads students/23n31a6645@mrcet.ac.in → is_registered: false
5. App redirects to Registration
6. User enters email → Receives OTP
7. User enters OTP → Verified
8. User sets password → Completes registration
9. Server returns profile → App calls applyProfile()
10. Dashboard loads → QR scanner available
11. Student scans QR → Attendance marked






Faculty vs Student App - Screen-by-Screen Flow Comparison
Screen Flow Comparison Table
Screen	Faculty App	Student App	Key Difference
1. App Launch	Shows Login Screen	Shows Login Screen	Same
2. Login Screen	User enters Email + Password (admin-provided)	User enters Email + Password (admin-provided)	Same
3. After Login Success	Firebase Auth returns token with email	Firebase Auth returns token with email	Same
4. Profile Load	Calls FacultyService.load() → reads faculties/{email} from Firestore	Calls StudentService.load() → reads students/{email} from Firestore	Different collection
5. Registration Check	Checks faculties/{email}.is_registered	Checks students/{email}.is_registered	Same logic, different collection
6. If NOT Registered	Redirects to Registration Flow	Redirects to Registration Flow	Same
7. Registration: Step 1	Enter email → POST /api/v1/Faculty/register/initiate	Enter email → POST /api/v1/Student/register/initiate	Different endpoint
8. Registration: Step 2	Enter OTP → POST /api/v1/Faculty/register/verify	Enter OTP → POST /api/v1/Student/register/verify	Different endpoint
9. Registration: Step 3	Set password → POST /api/v1/Faculty/register/complete<br>🔑 WITH Bearer Token header	Set password → POST /api/v1/Student/register/complete<br>❌ NO Bearer Token header	CRITICAL DIFFERENCE
10. Server Response	Returns profile dict + is_registered: true	Returns profile dict + is_registered: true	Same
11. Post-Registration	Calls FacultyService.applyProfile(profileData)	Calls StudentService.applyProfile(profileData)	Same
12. Dashboard	Shows Schedule, Start Session button	Shows QR Scanner, Attendance History	Different features
Key Differences Summary
Aspect	Faculty	Student	Why
Registration Endpoint	/Faculty/register/*	/Student/register/*	Role-specific routing
Step 3 Auth Gate	Firebase ID Token (Bearer header)	PIN verification only	Faculty pre-authenticated via Firebase
Firestore Collection	faculties/{email}	students/{email}	Separate profile storage
Profile Fields	department, designation, subjects	roll_number, section, year	Different metadata
Dashboard Features	Start sessions, view schedule	Scan QR, mark attendance	Different roles
Canonical ID	Email address	Email address	Same approach
Detailed Screen Flow
#	Screen	Faculty Flow	Student Flow	Notes
1	Splash	Loading animation	Loading animation	Same
2	Login	Email + Password fields	Email + Password fields	Same UI
3	Profile Check	faculties/{email} → check is_registered	students/{email} → check is_registered	Different collections
4a	Registration (if needed)	Full OTP flow + device binding	Full OTP flow + device binding	Same flow
4b	Registration Step 3	Attach Authorization: Bearer <firebase-token>	No Bearer token needed	KEY DIFFERENCE
5	Dashboard	Shows timetable, "Start Session" button	Shows QR scanner, attendance history	Different UI
6	Start Session (Faculty only)	POST /api/v1/faculty/start_session → get OTP	N/A	Faculty-only feature
7	Scan QR (Student only)	N/A	Scan QR → POST /api/v1/attendance/mark	Student-only feature
Registration Step 3 - The Critical Difference
Detail	Faculty	Student
Endpoint	POST /api/v1/Faculty/register/complete	POST /api/v1/Student/register/complete
Headers Required	Authorization: Bearer <firebase-id-token>	None
Body	{email, password, device_info}	{email, password, device_info}
Server Auth Gate	Validates Firebase token → extracts UID	Checks pin_verified_at (set in Step 2)
Why Different	Faculty already authenticated via Firebase before registration	Students authenticate via PIN flow
Post-Registration - What Happens
Step	Faculty	Student	Notes
Server writes to Firestore	faculties/{email} + faculty_profiles/{email} (dual-write)	students/{email} + student_profiles/{email} (dual-write)	Same pattern
Server writes to users	users/{email} with device_id, firebase_uid	users/{email} with device_id, firebase_uid	Same
Server creates Firebase Auth	Updates password, sets custom claims	Creates account, sets custom claims	Same
App receives response	{success, profile, is_registered}	{success, profile, is_registered}	Same
App updates state	FacultyService.applyProfile()	StudentService.applyProfile()	Same pattern
Navigation	Dashboard	Dashboard	Same
Daily Login Flow (After Registration)
Step	Faculty	Student	Notes
App opens	Firebase Auth restores session	Firebase Auth restores session	Same
Profile load	FacultyService.load() → Firestore + Hive cache	StudentService.load() → Firestore + Hive cache	Same pattern
Dashboard	Shows schedule, sessions	Shows QR scanner, attendance	Different features
API calls	All requests include Bearer token	All requests include Bearer token	Same
Device check	Server validates X-Device-ID	Server validates X-Device-ID	Same



 both faculty AND students are pre-provisioned, the current backend code has an architectural inconsistency:
The Problem
Aspect	Faculty	Student	Issue
Endpoint	/Faculty/register/complete	/Student/register/complete	Same structure
Bearer Token	Extracted and passed to service	NOT extracted	Student endpoint ignores it
Service Logic	Validates token if role == "faculty"	Only checks pin_verified_at	Hardcoded role check
Pre-provisioned?	YES	YES	Should behave the same!
The Code Problem
# Line 268: Only faculty gets token validation
if role == "faculty" and firebase_id_token:
    # Validate Firebase token → bypasses PIN check
elif not user_data.get("pin_verified_at"):
    # Students MUST have pin_verified_at (from OTP Step 2)
    raise HTTPException(400, "PIN_VERIFICATION_REQUIRED")
This means:
- Faculty with Firebase token → Registration succeeds (no PIN required)
- Students with Firebase token → Registration FAILS (still requires PIN)
- Students without PIN verification → Cannot complete registration
The Fix Needed
Both roles should support Firebase token authentication. The logic should be:
# If ANY user provides a valid Firebase token, skip PIN check
if firebase_id_token:
    decoded = auth.verify_id_token(firebase_id_token)
    if token_email != email:
        raise HTTPException(403, "Token email mismatch")
    firebase_uid_from_token = decoded.get("uid")
elif not user_data.get("pin_verified_at"):
    # Only require PIN if no Firebase token was provided
    raise HTTPException(400, "PIN_VERIFICATION_REQUIRED")
And the student endpoint needs to extract the Bearer token too:
@router.post("/student/register/complete")
async def complete_student_registration(
    http_request: Request, request: RegistrationCompleteRequest
):
    firebase_id_token = _extract_bearer_token(http_request)  # ADD THIS
    profile = await RegistrationService.complete_registration(
        email_input=request.email,
        password=request.password,
        device_info=request.device_info.model_dump(),
        role="student",
        firebase_id_token=firebase_id_token,  # PASS THIS

        