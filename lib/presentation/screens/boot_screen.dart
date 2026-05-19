import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'registration_screen.dart';
import 'idle_screen.dart';
import 'settings_screen.dart';
import '../../data/repositories/device_repository.dart';
import '../../services/api_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../core/security/firebase_rest_auth.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  final String _statusMessage = 'INITIALIZING SYSTEM...';
  String? _errorMessage;

  DeviceRegistration? _registration;
  bool _needsReauth = false;
  bool _isReauthenticating = false;
  String? _reauthError;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _performHandshake();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
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

      _registration = registration;

      // Step 2: Check Firebase auth tokens
      final hasToken = await FirebaseRestAuth.hasValidToken();
      if (!hasToken) {
        Log.w('[Boot] No Firebase auth tokens found. Showing login prompt.');
        if (mounted) {
          setState(() => _needsReauth = true);
        }
        return;
      }

      // Step 2.5: Server-side registration canary
      // Validates the board's Firestore document exists via GET /api/v1/board/ready
      // (which has a `Depends(BoardService.get_board_data)` auth guard).
      try {
        await ApiService.syncReadyCheck();
        Log.i('[Boot] Server-side registration confirmed for ${registration.smartBoardId}.');
      } on ApiException catch (e) {
        if (e.statusCode == 403) {
          Log.e('[Boot] Board not registered on server (403). Blocking transition.');
          if (mounted) {
            setState(() => _errorMessage = 'BOARD NOT REGISTERED\nThis device is not registered in the system.\nPlease contact IT Department.');
          }
          return;
        }
        Log.w('[Boot] Canary failed with ${e.statusCode}: ${e.userMessage}. Proceeding degraded.');
      } catch (e) {
        Log.w('[Boot] Canary network error: $e. Proceeding degraded.');
      }

      // Step 3: Instant UI Transition — local identity is valid.
      Log.i('[Boot] Local identity confirmed for ${registration.smartBoardId}. Entering Idle state.');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => IdleScreen(registration: registration)),
        );
      }

      // Step 4: Background Resynchronization
      // We perform network tasks asynchronously to ensure zero-lag startup
      _backgroundSync(deviceRepository);

    } catch (e) {
      Log.e('[Boot] Critical handshake error: $e');
      if (mounted) {
        setState(() => _errorMessage = 'SYSTEM INITIALIZATION FAILED\n$e');
      }
    }
  }

  Future<void> _reauthenticate() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;

    setState(() {
      _isReauthenticating = true;
      _reauthError = null;
    });

    try {
      final boardId = _registration!.smartBoardId;
      final email = AppConfig.boardIdToEmail(boardId);

      await FirebaseRestAuth.signInWithPassword(email, password);
      Log.i('[Boot] Re-authentication successful. Proceeding to IdleScreen.');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => IdleScreen(
              registration: _registration!,
            ),
          ),
        );
      }
    } on FirebaseRestAuthException catch (e) {
      setState(() {
        _isReauthenticating = false;
        _reauthError = e.code == 'INVALID_PASSWORD'
            ? 'Incorrect password'
            : 'Authentication failed: ${e.code}';
      });
    } catch (e) {
      setState(() {
        _isReauthenticating = false;
        _reauthError = 'Connection error. Check network.';
      });
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
                  if (!_needsReauth) ...[
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
                  ],
                  if (_needsReauth)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: _buildReauthForm(),
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

  Widget _buildReauthForm() {
    final boardId = _registration?.smartBoardId ?? 'UNKNOWN';
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 30, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 48),
          const SizedBox(height: 16),
          const Text(
            'SESSION EXPIRED',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your credentials to re-authenticate\nBoard: $boardId',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _reauthError,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.key),
            ),
            onChanged: (_) {
              if (_reauthError != null) setState(() => _reauthError = null);
            },
            onSubmitted: (_) => _reauthenticate(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isReauthenticating ? null : _reauthenticate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              child: _isReauthenticating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('LOGIN'),
            ),
          ),
        ],
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

                final repo = context.read<IDeviceRepository>();
                final nav = Navigator.of(context);
                await repo.clearRegistration();
                
                if (mounted) {
                  nav.pushReplacement(
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
