import 'lib/services/time_sync_service.dart';

void main() async {
  print('--- TRIGGERING NTP TIME SYNC ---');
  await TimeSyncService.synchronizeClock();
  
  final rawTime = DateTime.now();
  final trueTime = TimeSyncService.timeNow;
  
  print('\n[SYSTEM TIME vs TRUE TIME]');
  print('Uncorrected Windows Clock: $rawTime');
  print('Mathematically True Time:  $trueTime');
  print('Skew Adjusted: ${trueTime.difference(rawTime).inMilliseconds}ms');
}
