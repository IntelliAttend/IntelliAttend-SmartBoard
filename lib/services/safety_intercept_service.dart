import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class SafetyInterceptService {
  static final SafetyInterceptService _instance = SafetyInterceptService._internal();
  factory SafetyInterceptService() => _instance;
  SafetyInterceptService._internal();

  WebSocketChannel? _channel;
  final StreamController<String> _alertController = StreamController<String>.broadcast();
  Stream<String> get alertStream => _alertController.stream;

  /// Connects to the emergency alert WebSocket.
  void connect(String wsUrl) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        _alertController.add(message.toString());
      }, onError: (error) {
        print('❌ [SafetyIntercept] WebSocket Error: $error');
      }, onDone: () {
        print('📡 [SafetyIntercept] WebSocket Closed.');
      });
    } catch (e) {
      print('❌ [SafetyIntercept] Connection Failed: $e');
    }
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
