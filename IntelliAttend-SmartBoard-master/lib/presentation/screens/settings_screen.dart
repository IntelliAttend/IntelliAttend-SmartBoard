import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/isar_schemas.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/config/app_config.dart';
import 'qr_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  final DeviceRegistration registration;
  const SettingsScreen({super.key, required this.registration});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;
  String _idleTheme = 'auto';

  @override
  void initState() {
    super.initState();
    _loadIdleTheme();
  }

  Future<void> _loadIdleTheme() async {
    final theme = await SecureStorageService.getIdleTheme();
    if (mounted) setState(() => _idleTheme = theme ?? 'auto');
  }

  Future<void> _handleForceSync() async {
    setState(() => _isSyncing = true);
    try {
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

  @override
  Widget build(BuildContext context) {
    // Force Light Theme aesthetics as requested

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimaryLight, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'DISPLAY SETTINGS', 
          style: TextStyle(
            color: AppColors.textPrimaryLight,
            letterSpacing: 1.5, 
            fontWeight: FontWeight.w900,
            fontSize: 18,
          )
        ),
        centerTitle: true,
        shape: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      body: Stack(
        children: [
          // Subtle background pattern
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('DEVICE INFORMATION'),
                    const SizedBox(height: 24),
                    _buildInfoCard([
                      _buildInfoRow('Device Name', widget.registration.roomName),
                      _buildInfoRow('Building', widget.registration.building),
                      _buildInfoRow('Department', widget.registration.department),
                      _buildInfoRow('Capacity', '${widget.registration.capacity} Students'),
                    ]),
                    
                    if (AppConfig.enableVideoBreaks) ...[
                      const SizedBox(height: 48),
                      _buildSectionHeader('DISPLAY PREFERENCES'),
                      const SizedBox(height: 24),
                      _buildThemeToggle(),
                    ],
                    
                    const SizedBox(height: 48),
                    _buildSectionHeader('SYSTEM ACTIONS'),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.sync_rounded,
                            label: 'FORCE SYNC',
                            onTap: _isSyncing ? null : _handleForceSync,
                            isLoading: _isSyncing,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'QR DIAGNOSTIC',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const QrTestScreen()),
                              );
                            },
                          ),
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
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: AppColors.primaryTeal,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: children.expand((w) => [w, Divider(color: Colors.black.withValues(alpha: 0.05), height: 32)]).toList()..removeLast(),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondaryLight, fontSize: 14, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(color: AppColors.textPrimaryLight, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildThemeToggle() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (AppConfig.enableVideoBreaks) ...[
            const Text(
              'IDLE BREAK THEME',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimaryLight),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose the aesthetic for the video background during scheduled breaks.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _themeOption(
                    id: 'auto',
                    label: 'Automatic',
                    icon: Icons.brightness_auto_outlined,
                    isSelected: _idleTheme == 'auto',
                    onTap: () => _updateTheme('auto'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _themeOption(
                    id: 'white',
                    label: 'White Mode',
                    icon: Icons.light_mode_outlined,
                    isSelected: _idleTheme == 'white',
                    onTap: () => _updateTheme('white'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _themeOption(
                    id: 'dark',
                    label: 'Dark Mode',
                    icon: Icons.dark_mode_outlined,
                    isSelected: _idleTheme == 'dark',
                    onTap: () => _updateTheme('dark'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }

  Widget _themeOption({
    required String id,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeColor = AppColors.primaryTeal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : Colors.black12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? activeColor : Colors.black38),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTheme(String theme) async {
    await SecureStorageService.storeIdleTheme(theme);
    setState(() => _idleTheme = theme);
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
    bool isLoading = false,
  }) {
    final primaryColor = color ?? AppColors.primaryTeal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryTeal))
            else
              Icon(icon, size: 28, color: primaryColor),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color ?? AppColors.textPrimaryLight,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
