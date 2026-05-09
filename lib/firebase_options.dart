import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return macos; // macOS and iOS usually share same native config in this project
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Web config (Legacy/Reference)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8',
    appId: '1:738499328288:web:7a4c7b8c9d0e1f2a3b4c5d',
    messagingSenderId: '738499328288',
    projectId: 'intelliattend-a2564',
    authDomain: 'intelliattend-a2564.firebaseapp.com',
    storageBucket: 'intelliattend-a2564.firebasestorage.app',
    measurementId: 'G-7B8C9D0E1F',
  );

  // Native iOS/macOS config (EXTRACTED FROM GoogleService-Info.plist)
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8',
    appId: '1:738499328288:ios:7a4c7b8c9d0e1f2a3b4c5d',
    messagingSenderId: '738499328288',
    projectId: 'intelliattend-a2564',
    storageBucket: 'intelliattend-a2564.firebasestorage.app',
    iosBundleId: 'com.example.intelliattendSmartboard',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8',
    appId: '1:738499328288:android:7a4c7b8c9d0e1f2a3b4c5d',
    messagingSenderId: '738499328288',
    projectId: 'intelliattend-a2564',
    storageBucket: 'intelliattend-a2564.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8',
    appId: '1:738499328288:web:7a4c7b8c9d0e1f2a3b4c5d', // Windows often uses web-style config
    messagingSenderId: '738499328288',
    projectId: 'intelliattend-a2564',
    authDomain: 'intelliattend-a2564.firebaseapp.com',
    storageBucket: 'intelliattend-a2564.firebasestorage.app',
    measurementId: 'G-7B8C9D0E1F',
  );
}
