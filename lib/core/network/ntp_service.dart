
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:ntp/ntp.dart';

class NtpSyncService {
  Duration clockSkew = Duration.zero;

  // Sync with NTP (UDP) or HTTP (TCP) fallback
  Future<void> synchronizeClock(String fallbackUrl) async {
    try {
      // 1. Attempt UDP NTP sync (Google Time)
      final DateTime ntpTime = await NTP.now().timeout(const Duration(seconds: 3));
      _calculateSkew(ntpTime);
      print('✅ [NTP] UDP Sync Success. Skew: ${clockSkew.inMilliseconds}ms');
    } catch (e) {
      print('⚠️ [NTP] UDP Blocked (Firewall). Attempting HTTP Fallback...');
      
      // 2. HTTP Fallback (TCP Port 443)
      try {
        final response = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 5));
        
        // Use Date header from Server response
        final String? dateHeader = response.headers['date'];
        if (dateHeader != null) {
          final DateTime serverTime = DateTime.parse(dateHeader);
          _calculateSkew(serverTime);
          print('✅ [NTP] HTTP Fallback Success. Skew: ${clockSkew.inMilliseconds}ms');
        }
      } catch (e) {
        print('❌ [NTP] All sync methods failed. Using local system time.');
      }
    }
  }

  void _calculateSkew(DateTime synchronizedTime) {
    clockSkew = synchronizedTime.difference(DateTime.now());
  }

  DateTime get adjustedTime => DateTime.now().add(clockSkew);
}
