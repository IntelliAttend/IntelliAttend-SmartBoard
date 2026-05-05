# Firebase Setup Instructions for IntelliAttend SmartBoard

## Steps to Configure Firebase:

1. **Go to Firebase Console**: https://console.firebase.google.com/

2. **Create/Select Project**: 
   - Create a new project or select existing "IntelliAttend" project

3. **Add macOS App**:
   - Click "Add app" and select macOS
   - Bundle ID: `com.example.intelliattendSmartboard` (check your macos/Runner/Info.plist for actual bundle ID)
   - Download `GoogleService-Info.plist`

4. **Add the file to your project**:
   - Place `GoogleService-Info.plist` in: `macos/Runner/` directory
   - Ensure it's added to Xcode project (open Runner.xcworkspace in macos folder)

5. **Enable Firestore**:
   - In Firebase Console, go to Firestore Database
   - Create database in test mode (or production mode)
   - Create collection `rooms/{roomId}/live_override` with document `current`

6. **Required Firestore Structure**:
```
rooms/{roomId}/live_override/current
{
  "has_override": false,
  "new_faculty": "",
  "new_course": "",
  "override_reason": ""
}
```

## Alternative: Quick Test Without Firebase

If you want to test real-time updates without Firebase, the app will work with local data. The Firebase integration enables:
- Live roster updates
- Real-time override notifications
- Cross-device synchronization

## Current Status

The app is running in OFFLINE MODE. To enable live features:
1. Complete Firebase setup above
2. Restart the app with `flutter run -d macos`
