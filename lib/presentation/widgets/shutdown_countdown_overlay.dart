import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/platform/power_command_service.dart';

class ShutdownCountdownOverlay extends StatefulWidget {
  final Widget child;
  const ShutdownCountdownOverlay({super.key, required this.child});

  @override
  State<ShutdownCountdownOverlay> createState() =>
      _ShutdownCountdownOverlayState();
}

class _ShutdownCountdownOverlayState extends State<ShutdownCountdownOverlay> {
  final PowerCommandService _powerCmd = PowerCommandService();
  PowerCommandState _state = const PowerCommandState();
  StreamSubscription<PowerCommandState>? _sub;
  bool _showConfirmCancel = false;

  @override
  void initState() {
    super.initState();
    _state = _powerCmd.currentState;
    _sub = _powerCmd.onStateChanged.listen((s) {
      if (mounted) {
        setState(() {
          _state = s;
          if (s.status != PowerCommandStatus.pendingShutdown) {
            _showConfirmCancel = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_state.status == PowerCommandStatus.pendingShutdown)
          _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    final fraction = _state.totalSeconds > 0
        ? _state.secondsRemaining / _state.totalSeconds
        : 1.0;

    return Positioned.fill(
      child: Material(
        color: Colors.black87,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.power_settings_new_rounded,
                    size: 120, color: Colors.redAccent),
                const SizedBox(height: 32),
                Text(
                  'System Shutdown',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (_state.reason != null && _state.reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: Text(
                      _state.reason!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: CircularProgressIndicator(
                          value: fraction,
                          strokeWidth: 12,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _state.secondsRemaining <= 10
                                ? Colors.redAccent
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      Text(
                        '${_state.secondsRemaining}',
                        style: Theme.of(context)
                            .textTheme
                            .displayLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 80,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'seconds remaining',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 56),
                if (_showConfirmCancel)
                  SizedBox(
                    width: 360,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Cancel Shutdown?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The admin-requested system shutdown will be cancelled.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => setState(
                                      () => _showConfirmCancel = false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(
                                        color: Colors.white24),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  child: const Text('Keep Shutting Down',
                                      style: TextStyle(fontSize: 15)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () {
                                    _showConfirmCancel = false;
                                    _powerCmd.cancelFromLocal();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.redAccent,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 6,
                                  ),
                                  child: const Text('Cancel Shutdown',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 64,
                    width: 300,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          setState(() => _showConfirmCancel = true),
                      icon: const Icon(Icons.close, size: 28),
                      label: const Text('Cancel Shutdown',
                          style: TextStyle(fontSize: 20)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
