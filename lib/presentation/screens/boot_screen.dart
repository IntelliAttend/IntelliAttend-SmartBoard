import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import 'registration_screen.dart';
import 'idle_screen.dart';
import 'settings_screen.dart';
import '../../data/repositories/device_repository.dart';
import '../../services/api_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';

class BootScreen extends StatefulWidget {
  final bool isDegraded;
  const BootScreen({super.key, this.isDegraded = false});

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
    final deviceRepository = context.read<IDeviceRepository>();
    try {
      // Step 1: Rapid Local Check — Isar registration record
      final registration = await deviceRepository.getRegistration();
      final isRegistered = registration != null &&
          registration.smartBoardId.isNotEmpty &&
          registration.smartBoardId != 'UNKNOWN';

      if (!isRegistered) {
        Log.i('[Boot] No local registration found. Redirecting to Registration.');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          );
        }
        return;
      }

      // Step 2: Token validity check — if the device was logged-out or the
      // access/refresh tokens are missing, treat it as unregistered and send
      // the admin back to the Registration screen. This prevents landing on
      // the Idle screen with no valid server identity.
      final hasToken = await SecureStorageService.getRefreshToken() != null;
      if (!hasToken) {
        Log.w('[Boot] Registration record found but no auth token. Forcing re-registration.');
        // Clear the stale Isar entry so next boot starts clean.
        await deviceRepository.clearRegistration();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          );
        }
        return;
      }

      // Step 3: Instant UI Transition — local identity is valid.
      Log.i('[Boot] Local identity confirmed for ${registration.smartBoardId}. Entering Idle state.');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => IdleScreen(registration: registration, isDegraded: widget.isDegraded)),
        );
      }

      // Step 3: Background Resynchronization
      // We perform network tasks asynchronously to ensure zero-lag startup
      _backgroundSync(deviceRepository);

    } catch (e) {
      Log.e('[Boot] Critical handshake error: $e');
      if (mounted) {
        setState(() => _errorMessage = 'SYSTEM INITIALIZATION FAILED\n$e');
      }
    }
  }

  Future<void> _backgroundSync(IDeviceRepository repository) async {
    try {
      // Try to refresh the timetable and check for server-side revocation
      await repository.syncTimetable(fullSync: false);
      Log.i('[Boot] Background sync completed successfully.');
    } catch (e) {
      // If network fails, we stay in "Degraded" mode but REMAIN logged in locally
      Log.w('[Boot] Background sync failed. Operating in Offline Mode: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.bgLight,
        child: Stack(
          children: [
            // Background pattern
            Opacity(
              opacity: 0.02,
              child: Center(
                child: Image.asset(
                  'assets/background.png',
                  width: 400,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // Top Left Settings Button
            Positioned(
              top: 40,
              left: 40,
              child: Consumer<IDeviceRepository>(
                builder: (context, deviceRepository, child) {
                  return FutureBuilder<DeviceRegistration?>(
                    future: deviceRepository.getRegistration(),
                    builder: (context, snapshot) {
                      return Tooltip(
                        message: 'System Settings',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              final reg = snapshot.data ?? (DeviceRegistration()
                                ..smartBoardId = 'UNREGISTERED'
                                ..roomName = 'New Device'
                                ..building = 'Unknown'
                                ..department = 'Unknown'
                                ..hardwareId = 'Unknown');
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => SettingsScreen(registration: reg),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: const Icon(Icons.settings_outlined, color: AppColors.textPrimaryLight, size: 28),
                            ),
                          ),
                        ),
                      );
                    },
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
                      ),
                      child: const Icon(
                        Icons.settings_input_antenna_rounded,
                        size: 80,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'INTELLIATTEND',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: AppColors.textPrimaryLight,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondaryLight,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 64),
                  const SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 2,
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: _buildErrorDisplay(),
                    ),
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
                  child: Text('v5.4.1-STABLE', style: Theme.of(context).textTheme.labelLarge),
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
      constraints: const BoxConstraints(maxWidth: 600),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 24),
          const Text(
            'SYSTEM CONFIGURATION REQUIRED',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!.contains('404') || _errorMessage!.toLowerCase().contains('configured')
                ? 'This device is not yet configured for this classroom.\nPlease contact the IT Department or System Administrator.'
                : _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => _performHandshake(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('RETRY INITIALIZATION'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showWipeConfirmation() {
    final pinController = TextEditingController();
    bool isVerifying = false;
    String? pinError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Security Authorization Required', style: TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter Administrative PIN to authorize system wipe. This will permanently revoke this board\'s credentials.'),
              const SizedBox(height: 24),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Admin PIN',
                  errorText: pinError,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.security),
                ),
                onChanged: (_) {
                  if (pinError != null) setDialogState(() => pinError = null);
                },
              ),
              if (isVerifying)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: isVerifying ? null : () async {
                final pin = pinController.text;
                if (pin.length < 6) {
                  setDialogState(() => pinError = 'Enter 6-digit PIN');
                  return;
                }

                setDialogState(() => isVerifying = true);
                
                final isValid = await ApiService.verifyAdminPin(pin);
                
                if (!isValid) {
                  setDialogState(() {
                    isVerifying = false;
                    pinError = 'Invalid Authorization PIN';
                  });
                  return;
                }

                // Authorized: Proceed with server-side revocation and local wipe
                try {
                  await ApiService.deregisterBoard();
                } catch (e) {
                  Log.w('⚠️ [Boot] Server-side revocation failed: $e');
                  // We continue with local wipe anyway to ensure device is cleared
                }

                await context.read<IDeviceRepository>().clearRegistration();
                
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('AUTHORIZE WIPE'),
            ),
          ],
        ),
      ),
    );
  }
}
