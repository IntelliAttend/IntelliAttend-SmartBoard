import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/auth/token_manager.dart';
import '../../core/errors/auth_exceptions.dart';
import 'registration_screen.dart';
import 'login_screen.dart';
import 'session_orchestrator_screen.dart';
import '../../data/repositories/device_repository.dart';
import '../../services/api_service.dart';
import '../../core/utils/logger.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  final String _statusMessage = 'INITIALIZING SYSTEM...';
  String? _errorMessage;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _performHandshake();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version}+${info.buildNumber}');
      }
    } catch (_) {}
  }

  Future<void> _performHandshake() async {
    final deviceRepository = context.read<IDeviceRepository>();
    try {
      // Step 1: Rapid Local Check (OS-style persistence)
      final registration = await deviceRepository.getRegistration();
      final isRegistered = registration != null && registration.smartBoardId.isNotEmpty;

      if (!isRegistered) {
        Log.i('[Boot] No local registration found. Redirecting to Registration.');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const RegistrationScreen(),
              transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
        return;
      }

      // Step 2: Verify auth — if credentials are invalid, show login screen
      Log.i('[Boot] Verifying authentication...');
      try {
        await TokenManager().getValidToken();
        Log.i('[Boot] Auth verified.');
      } on NoCredentialsException {
        Log.i('[Boot] No credentials stored. Showing login screen.');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LoginScreen(),
              transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
        return;
      } on InvalidCredentialsException {
        Log.i('[Boot] Invalid credentials. Showing login screen.');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LoginScreen(),
              transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
        return;
      }

      // Step 3: Minimum splash display + wait just long enough for the logo
      // to render and the user to register it.
      Log.i('[Boot] Local identity confirmed for ${registration.smartBoardId}. Splash display.');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Step 4: Smooth fade transition to the orchestrator
      Log.i('[Boot] Splash complete. Entering Orchestrator.');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => SessionOrchestratorScreen(registration: registration),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }

      // Step 5: Background Resynchronization (runs in background, not blocking)
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
      // Full hydration — downloads timetable + rosters + profile in one call.
      // Uses manifest_hash to skip re-processing if nothing changed.
      await repository.hydrateFromServer();
      Log.i('[Boot] Background hydration completed successfully.');
    } catch (e) {
      Log.w('[Boot] Background hydration failed. Operating in Offline Mode: $e');
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

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onLongPress: () => _showWipeConfirmation(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/logo_square.png',
                        width: 500,
                        height: 500,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image, size: 80, color: Colors.red),
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
                  child: Text(_appVersion.isNotEmpty ? _appVersion : 'v--', style: Theme.of(context).textTheme.labelLarge),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 30, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
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
                
                final repo = context.read<IDeviceRepository>();
                final navigator = Navigator.of(context);
                
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
                }

                await repo.clearRegistration();

                if (mounted) {
                  navigator.pushReplacement(
                    MaterialPageRoute(builder: (_) => const RegistrationScreen()),
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
