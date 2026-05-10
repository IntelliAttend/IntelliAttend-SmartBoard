# Firebase Quick Setup for IntelliAttend SmartBoard

## Option 1: Use Firebase CLI (Recommended)

```bash
# Install Firebase CLI if not installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase in your project
cd "/Users/balaseetharamanjaneyulu/Dev/IntelliAttend /IntelliAttend-SmartBoard"
firebase init firestore

# Then add macOS app in Firebase Console
```

## Option 2: Manual Setup (Faster)

1. **Go to Firebase Console**: https://console.firebase.google.com/

2. **Create/Open Project**: 
   - Create new project "IntelliAttend" or open existing

3. **Add macOS App**:
   - Click "Add app" → Select macOS icon 🖥️
   - Bundle ID: Check `macos/Runner.xcodeproj/project.pbxproj` for PRODUCT_BUNDLE_IDENTIFIER
   - Download `GoogleService-Info.plist`

4. **Add Plist to Project**:
```bash
# Copy the downloaded file to:
cp ~/Downloads/GoogleService-Info.plist "/Users/balaseetharamanjaneyulu/Dev/IntelliAttend /IntelliAttend-SmartBoard/macos/Runner/GoogleService-Info.plist"
```

5. **Register in Xcode**:
```bash
open "/Users/balaseetharamanjaneyulu/Dev/IntelliAttend /IntelliAttend-SmartBoard/macos/Runner.xcworkspace"
# In Xcode: File → Add Files to "Runner" → Select GoogleService-Info.plist
```

6. **Enable Firestore**:
   - Firebase Console → Firestore Database → Create Database
   - Start in "test mode" for development

7. **Create Test Data** (Optional - for real-time updates):
```
Firestore Collection: rooms
  Document: CSE-45
    Subcollection: live_override
      Document: current
      {
        "has_override": false,
        "new_faculty": "",
        "new_course": "",
        "override_reason": ""
      }
```

8. **Restart App**:
```bash
flutter run -d macos
```

## Current Status
✅ UI Overflow Fixed
✅ App Running on macOS
⚠️  Firebase needs GoogleService-Info.plist

The app works in OFFLINE MODE without Firebase. Real-time features activate once Firebase is configured.
