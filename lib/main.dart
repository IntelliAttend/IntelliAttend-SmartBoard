
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/attendance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const IntelliAttendApp());
}

class IntelliAttendApp extends StatelessWidget {
  const IntelliAttendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntelliAttend SmartBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Landing at the AttendanceScreen for demonstration
      // In production, this would land on LoginScreen (OTP entry)
      home: const AttendanceScreen(
        sessionId: 'SESS_411A_DEMO',
        sessionSecret: 'Z9#KL2!PQ8RX\$MN5',
        rosterCount: 50,
      ),
    );
  }
}
