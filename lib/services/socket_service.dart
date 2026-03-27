import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

class SocketService {
  late IO.Socket socket;
  final _attendanceStreamController = StreamController<Map<String, dynamic>>.broadcast();

  /// A live pipeline of successfully verified student scans.
  /// The `AttendanceScreen` can listen to this to reactively paint grid squares green.
  Stream<Map<String, dynamic>> get attendanceStream => _attendanceStreamController.stream;

  void connect() {
    print('[SocketService] Connecting to the Node.js Megaphone...');
    
    socket = IO.io('ws://127.0.0.1:3000', IO.OptionBuilder()
        .setTransports(['websocket']) // Force strict explicit websocket
        .disableAutoConnect()
        .build());

    socket.connect();

    socket.onConnect((_) {
      print('[SocketService] Connected strongly to Node.js.');
    });

    // The single event that matters: Python verifying a student and Node.js shouting it to us.
    socket.on('attendance_success', (data) {
      if (data is Map<String, dynamic>) {
        print('[SocketService] Flash! Verified Scan: \$data');
        _attendanceStreamController.add(data);
      }
    });

    socket.onDisconnect((_) => print('[SocketService] Disconnected.'));
  }

  void disconnect() {
    socket.disconnect();
    socket.dispose();
    _attendanceStreamController.close();
  }
}
