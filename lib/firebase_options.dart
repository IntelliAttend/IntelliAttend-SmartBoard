import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions fromConfig({
    required String apiKey,
    required String projectId,
  }) {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: '1:738499328288:web:7a4c7b8c9d0e1f2a3b4c5d',
      messagingSenderId: '738499328288',
      projectId: projectId,
      authDomain: '$projectId.firebaseapp.com',
      storageBucket: '$projectId.firebasestorage.app',
    );
  }
}
