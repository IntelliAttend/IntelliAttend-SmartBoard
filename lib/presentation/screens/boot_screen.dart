import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'registration_screen.dart';
import 'idle_screen.dart';
import 'settings_screen.dart';
import '../../services/device_service.dart';
import '../../models/isar_schemas.dart';
import '../widgets/glass_container.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  final String _statusMessage = 'INITIALIZING SYSTEM...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _performHandshake();
  }

  Future<void> _performHandshake() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      final isRegistered = await DeviceService.isRegistered();

      if (!isRegistered) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          );
        }
        return;
      }

      final registration = await DeviceService.getRegistration();
      if (registration == null) {
        if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const RegistrationScreen()));
        return;
      }

      try {
        await DeviceService.syncTimetable();
      } catch (e) {
        debugPrint('⚠️ [Boot] Timetable sync failed: $e');
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => IdleScreen(registration: registration)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error: $e');
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _errorMessage = null);
            _performHandshake();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.background, Color(0xFF1E293B)],
          ),
        ),
        child: Stack(
          children: [
            // Settings Button (Top Left)
            Positioned(
              top: 24,
              left: 24,
              child: FutureBuilder<DeviceRegistration?>(
                future: DeviceService.getRegistration(),
                builder: (context, snapshot) {
                  // Only show if registered, or show dummy registration if not
                  return Tooltip(
                    message: 'System Settings',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          final reg = snapshot.data ?? DeviceRegistration()
                            ..roomId = 'UNREGISTERED'
                            ..roomName = 'New Device'
                            ..building = 'Unknown'
                            ..department = 'Unknown'
                            ..hardwareId = 'Unknown';
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => SettingsScreen(registration: reg),
                            ),
                          );
                        },
                        child: GlassContainer(
                          padding: const EdgeInsets.all(12),
                          borderRadius: 12,
                          child: const Icon(Icons.settings_outlined, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onLongPress: () => _showWipeConfirmation(),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 10),
                        ],
                      ),
                      child: const Icon(Icons.security_rounded, size: 84, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 64),
                  const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
                  const SizedBox(height: 48),
                  Text(
                    'INTELLIATTEND',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w900, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 4, color: AppColors.textMuted),
                  ),
                  if (_errorMessage != null) _buildErrorDisplay(),
                ],
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Opacity(
                  opacity: 0.3,
                  child: Text('v5.4.1-DEBUG', style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 32, left: 48, right: 48),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        _errorMessage!,
        style: const TextStyle(color: AppColors.error, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showWipeConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Wipe Registration?'),
        content: const Text('This will clear all local data and require re-registration. Use only for troubleshooting.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await DeviceService.clearRegistration();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('WIPE DATA'),
          ),
        ],
      ),
    );
  }
}
