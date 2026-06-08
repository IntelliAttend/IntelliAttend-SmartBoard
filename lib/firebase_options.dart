import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions fromConfig({
    required String apiKey,
    required String projectId,
    required String appId,
    required String messagingSenderId,
  }) {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: '$projectId.firebaseapp.com',
      storageBucket: '$projectId.firebasestorage.app',
    );
  }
}
