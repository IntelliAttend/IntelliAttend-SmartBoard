import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class InitFailureScreen extends StatelessWidget {
  final String message;
  const InitFailureScreen({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text('System Initialization Failed',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    await windowManager.destroy();
                  },
                  child: const Text('Close Application'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
