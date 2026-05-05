import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_service.dart';
import '../../models/isar_schemas.dart';
import '../widgets/glass_container.dart';
import 'registration_screen.dart';

class SettingsScreen extends StatefulWidget {
  final DeviceRegistration registration;
  const SettingsScreen({super.key, required this.registration});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;
  bool _isFullScreen = true;

  @override
  void initState() {
    super.initState();
    _checkFullScreen();
  }

  Future<void> _checkFullScreen() async {
    final isFull = await windowManager.isFullScreen();
    if (mounted) setState(() => _isFullScreen = isFull);
  }

  Future<void> _handleForceSync() async {
    setState(() => _isSyncing = true);
    try {
      await DeviceService.syncTimetable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timetable synced successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _toggleFullScreen() async {
    final willBeFull = !_isFullScreen;
    await windowManager.setFullScreen(willBeFull);
    setState(() => _isFullScreen = willBeFull);
  }

  void _showWipeConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Wipe Registration?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will clear local display data. Action cannot be undone.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await DeviceService.clearRegistration();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('WIPE DEVICE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('DISPLAY SETTINGS', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.background, Color(0xFF1E293B)],
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('DEVICE INFORMATION'),
                    const SizedBox(height: 24),
                    _buildInfoCard([
                      _buildInfoRow('Room ID', widget.registration.roomId),
                      _buildInfoRow('Device Name', widget.registration.roomName),
                      _buildInfoRow('Building', widget.registration.building),
                    ]),
                    
                    const SizedBox(height: 48),
                    _buildSectionHeader('ACTIONS'),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildActionButton(
                          icon: Icons.sync_rounded,
                          label: 'FORCE SYNC',
                          onTap: _isSyncing ? null : _handleForceSync,
                          isLoading: _isSyncing,
                        ),
                        _buildActionButton(
                          icon: _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                          label: _isFullScreen ? 'EXIT FULL SCREEN' : 'ENTER FULL SCREEN',
                          onTap: _toggleFullScreen,
                        ),
                        _buildActionButton(
                          icon: Icons.delete_forever_rounded,
                          label: 'RESET DEVICE',
                          onTap: _showWipeConfirmation,
                          color: AppColors.error,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: children.expand((w) => [w, const Divider(color: Colors.white10, height: 32)]).toList()..removeLast(),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassContainer(
        width: 220,
        padding: const EdgeInsets.all(24),
        borderColor: color?.withValues(alpha: 0.3),
        child: Column(
          children: [
            isLoading 
              ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 32, color: color ?? AppColors.primary),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.white,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
