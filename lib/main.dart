import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'services/session_manager.dart';
import 'models/isar_schemas.dart';
import 'presentation/screens/kiosk_home_screen.dart';
import 'presentation/screens/attendance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Isar Vault (Phase 3)
  await SessionManager.init();

  // 2. Initialize Firebase
  try {
    await Firebase.initializeApp();
    print('[Firebase] Initialized Successfully.');
  } catch (e) {
    print('[Firebase] Initialization Warning: ${e}.');
  }

  // 3. Crash Recovery Check
  final activeSession = await SessionManager.getResumeableSession();
  String? secret;
  if (activeSession != null) {
    secret = await SessionManager.getSessionSecret(activeSession.sessionId);
  }

  runApp(IntelliAttendApp(resumeSession: activeSession, sessionSecret: secret));
}

class IntelliAttendApp extends StatelessWidget {
  final ActiveSession? resumeSession;
  final String? sessionSecret;

  const IntelliAttendApp({super.key, this.resumeSession, this.sessionSecret});

  @override
  Widget build(BuildContext context) {
    // Create local variables for type promotion
    final session = resumeSession;
    final secret = sessionSecret;

    return MaterialApp(
      title: 'IntelliAttend SmartBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Auto-Resume logic: If we have a session + secret, jump straight to grid
      home: (session != null && secret != null)
          ? AttendanceScreen(
              sessionId: session.sessionId,
              sessionSecret: secret,
              rosterCount: session.rosterCount,
              initialVerifiedIds: session.verifiedStudentIds,
            )
          : const KioskHomeScreen(),
    );
  }
}
