import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../core/theme/app_theme.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../data/repositories/auth_repository.dart';
import '../../models/isar_schemas.dart';
import '../../models/remote_config.dart';
import '../../services/hydration_service.dart';
import '../../services/timetable_cache.dart';
import '../../services/network_info_service.dart';
import '../../services/hotspot_service.dart';
import '../../services/auto_updater.dart';
import 'package:number_flow/number_flow.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;
  String _idleTheme = 'auto';
  HydrationProfile? _profile;
  DeviceRegistration? _registration;

  NetworkInfo _networkInfo = NetworkInfo(isConnected: false, lastChecked: DateTime.now());
  StreamSubscription<NetworkInfo>? _networkSub;
  Timer? _speedTimer;


  @override
  void initState() {
    super.initState();
    _loadData();
    _startNetworkMonitoring();
    _checkHotspotState();
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _speedTimer?.cancel();
    _holdTimer?.cancel();
    _syncResetTimer?.cancel();
    super.dispose();
  }

  void _startNetworkMonitoring() {
    final service = NetworkInfoService();
    service.startMonitoring(interval: const Duration(seconds: 8));
    _networkSub = service.onChanged.listen((info) {
      if (mounted) setState(() => _networkInfo = info);
    });
    _networkInfo = service.current;
  }

  Future<void> _loadData() async {
    await _loadIdleTheme();
    await _loadDeviceInfo();
  }

  Future<void> _loadIdleTheme() async {
    final theme = await SecureStorageService.getIdleTheme();
    if (mounted) setState(() => _idleTheme = theme ?? 'auto');
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final isar = Isar.getInstance();
      if (isar == null) return;

      final profile = await isar.hydrationProfiles.where().findFirst();
      final registration = await isar.deviceRegistrations.where().findFirst();

      if (mounted) {
        setState(() {
          _profile = profile;
          _registration = registration;
        });
      }
    } catch (e) {
      Log.e('[Settings] Failed to load device info: $e');
    }
  }

  bool _hotspotEnabled = false;
  bool _hotspotToggling = false;
  bool _passwordVisible = false;

  Timer? _holdTimer;
  double _holdProgress = 0.0;
  bool _isHolding = false;
  String? _holdAction;

  // Hidden 45s hold-to-reset on sync button
  Timer? _syncResetTimer;
  bool _isSyncHoldActive = false;

  String get _hotspotName {
    final room = _profile?.roomNumber ?? _registration?.roomName ?? '0000';
    return 'IntelliAttend-$room';
  }

  String get _hotspotPassword {
    final room = _profile?.roomNumber ?? _registration?.roomName ?? '0000';
    return 'Choice@$room';
  }


  Future<void> _handleSyncTimetable() async {
    setState(() => _isSyncing = true);
    try {
      final isar = Isar.getInstance();
      if (isar == null) throw Exception('Database not initialized');

      final result = await HydrationService.hydrate(isar: isar);

      if (result.changed) {
        final allEntries = await isar.timetableEntrys
            .where()
            .sortByDayOfWeek()
            .thenByStartTime()
            .findAll();
        TimetableCache().updateAll(allEntries);

        // Re-load profile + registration so hotspot name/password
        // and device info card reflect the fresh hydration data.
        await _loadDeviceInfo();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Timetable synced — ${allEntries.length} slots loaded'),
              backgroundColor: AppColors.primaryTeal,
            ),
          );
        }
      } else if (result.fromCache) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Timetable already up to date')),
          );
        }
      } else {
        throw Exception(result.error ?? 'Unknown error');
      }
    } catch (e) {
      Log.e('[Settings] Sync failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'SETTINGS',
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
                    _buildSectionHeader('NETWORK STATUS'),
                    const SizedBox(height: 24),
                    _buildNetworkCard(),

                    const SizedBox(height: 48),
                    _buildSectionHeader('HOTSPOT'),
                    const SizedBox(height: 24),
                    _buildHotspotCard(),

                    const SizedBox(height: 48),
                    _buildSectionHeader('DEVICE INFORMATION'),
                    const SizedBox(height: 24),
                    _buildInfoCard([
                      _buildInfoRow('SmartBoard ID', _registration?.smartBoardId ?? 'Unknown'),
                      _buildInfoRow('Room', _profile?.roomNumber ?? _registration?.roomName ?? 'Unknown'),
                      _buildInfoRow('Building', _profile?.building ?? _registration?.building ?? 'Unknown'),
                      _buildInfoRow('Department', _registration?.department ?? 'Unknown'),
                      _buildInfoRow('Capacity', '${_registration?.capacity ?? 0} Students'),
                      _buildInfoRow('Institution', _profile?.institutionName ?? 'Unknown'),
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
                    _buildSyncButton(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHoldActionButton(
                            icon: Icons.power_settings_new_rounded,
                            label: 'POWER OFF',
                            action: 'shutdown',
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildHoldActionButton(
                            icon: Icons.restart_alt_rounded,
                            label: 'RESTART',
                            action: 'restart',
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),

                    _buildUpdateSection(),
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

  Widget _buildSyncButton() {
    return GestureDetector(
      onTap: _isSyncing ? null : _handleSyncTimetable,
      onLongPressStart: _isSyncing ? null : (_) => _startSyncResetHold(),
      onLongPressEnd: (_) => _cancelSyncResetHold(),
      onLongPressCancel: _cancelSyncResetHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: _isSyncHoldActive
              ? AppColors.error.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isSyncHoldActive
                ? AppColors.error.withValues(alpha: 0.3)
                : AppColors.primaryTeal.withValues(alpha: 0.1),
            width: _isSyncHoldActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isSyncHoldActive ? AppColors.error : AppColors.primaryTeal)
                  .withValues(alpha: _isSyncHoldActive ? 0.1 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSyncing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryTeal,
                ),
              )
            else
              Icon(
                _isSyncHoldActive ? Icons.lock_outline_rounded : Icons.sync_rounded,
                size: 22,
                color: _isSyncHoldActive ? AppColors.error : AppColors.primaryTeal,
              ),
            const SizedBox(width: 12),
            Text(
              'SYNC',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _isSyncHoldActive ? AppColors.error : AppColors.primaryTeal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startSyncResetHold() {
    _syncResetTimer?.cancel();
    _isSyncHoldActive = true;
    setState(() {});
    _syncResetTimer = Timer(const Duration(seconds: 45), () {
      _isSyncHoldActive = false;
      setState(() {});
      _handleResetDevice();
    });
  }

  void _cancelSyncResetHold() {
    _syncResetTimer?.cancel();
    if (_isSyncHoldActive) {
      _isSyncHoldActive = false;
      setState(() {});
    }
  }

  Future<void> _handleResetDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 10),
            const Text('Factory Reset?'),
          ],
        ),
        content: const Text(
          'This will erase all local data on this SmartBoard and return it to the setup screen.\n\n'
          'You will need the Board ID and new password to re-register.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('RESET NOW'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final isar = Isar.getInstance();
      if (isar == null) throw Exception('Database not initialized');

      final authRepo = AuthRepository(
        ApiClient(),
      );
      await authRepo.deregister(isar);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device reset. Restarting...'),
            backgroundColor: AppColors.primaryTeal,
          ),
        );

        await Future.delayed(const Duration(seconds: 1));
      }

      // Exit the app so the next launch is a completely fresh process —
      // identical to first-time install. All local data (Isar, SecureStorage,
      // singletons) is already cleared by deregister(). On relaunch the app
      // detects no registration and shows the login screen.
      exit(0);
    } catch (e) {
      Log.e('[Settings] Factory reset failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildNetworkCard() {
    final info = _networkInfo;
    final isConnected = info.isConnected;
    final hasInternet = info.hasInternet;
    final statusColor = !isConnected
        ? AppColors.error
        : !hasInternet
            ? const Color(0xFFF59E0B)
            : AppColors.primaryTeal;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _connectionIcon(info),
                  color: statusColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.displaySsid,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${info.connectionType} • ${info.hasInternet ? info.speedLabel : info.speedLabel}${info.mbpsLabel.isNotEmpty ? ' • ${info.mbpsLabel}' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(info.speedLabel, statusColor),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.black.withValues(alpha: 0.05), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMetricItem(Icons.speed_rounded, 'Latency', info.isConnected ? info.latencyLabel : '—'),
              const SizedBox(width: 24),
              _buildRealTimeSpeedItem(info),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondaryLight),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimaryLight)),
          ],
        ),
      ],
    );
  }

  Widget _buildRealTimeSpeedItem(NetworkInfo info) {
    return Row(
      children: [
        const Icon(Icons.downloading_rounded, size: 16, color: AppColors.textSecondaryLight),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Speed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight)),
            NumberFlow(
              value: info.realTimeMbps,
              decimalPlaces: info.realTimeMbps >= 10 ? 0 : 1,
              suffix: ' Mbps',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimaryLight),
              spinDuration: const Duration(milliseconds: 500),
              spinCurve: Curves.easeOut,
              transformDuration: const Duration(milliseconds: 350),
              transformCurve: Curves.easeOut,
              opacityDuration: const Duration(milliseconds: 250),
              opacityCurve: Curves.easeOut,
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildHotspotCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryTeal.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: AppColors.primaryTeal,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Student Hotspot',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryLight,
                  ),
                ),
              ),
              if (_hotspotToggling)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryTeal),
                )
              else
                Switch(
                  value: _hotspotEnabled,
                  activeThumbColor: AppColors.primaryTeal,
                  onChanged: _toggleHotspot,
                ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.black.withValues(alpha: 0.05), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.wifi_rounded, size: 18, color: AppColors.primaryTeal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Network Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight)),
                    const SizedBox(height: 2),
                    Text(
                      _hotspotName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hotspotEnabled) ...[
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.primaryTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight)),
                      const SizedBox(height: 2),
                      Text(
                        _passwordVisible ? _hotspotPassword : '••••••••',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryLight,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 18,
                  ),
                  color: AppColors.textSecondaryLight,
                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkHotspotState() async {
    if (!Platform.isWindows) return;
    try {
      final enabled = await HotspotService().isEnabled();
      if (mounted) setState(() => _hotspotEnabled = enabled);
    } catch (e) {
      Log.w('[Settings] Failed to check hotspot state: $e');
    }
  }

  Future<void> _toggleHotspot(bool enabled) async {
    setState(() => _hotspotToggling = true);
    try {
      if (!Platform.isWindows) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hotspot control is only available on Windows')),
          );
        }
        return;
      }

      final service = HotspotService();
      if (enabled) {
        await service.start(ssid: _hotspotName, password: _hotspotPassword);
      } else {
        await service.stop();
      }

      await _checkHotspotState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_hotspotEnabled ? 'Hotspot enabled: $_hotspotName' : 'Hotspot disabled'),
            backgroundColor: AppColors.primaryTeal,
          ),
        );
      }
    } on HotspotException catch (e) {
      Log.e('[Settings] Hotspot toggle failed: $e');
      if (mounted) {
        if (e.isAdminRequired) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Administrator Required'),
              content: const Text(
                'Hotspot control requires the app to run as Administrator.\n\n'
                'Right-click the app and select "Run as administrator", or '
                'configure auto-elevate in the app shortcut properties.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Process.run('powershell', [
                      '-NoProfile', '-Command',
                      'Start-Process "ms-settings:network-mobilehotspot"',
                    ]);
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to toggle hotspot: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      Log.e('[Settings] Hotspot toggle failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle hotspot: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _hotspotToggling = false);
    }
  }

  IconData _connectionIcon(NetworkInfo info) {
    if (!info.isConnected) return Icons.wifi_off_rounded;
    if (info.connectionType == 'Ethernet') return Icons.lan_rounded;
    if (info.connectionType == 'WiFi') return Icons.wifi_rounded;
    return Icons.wifi_rounded;
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textPrimaryLight, fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.end,
          ),
        ),
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
    double height = 120,
  }) {
    final primaryColor = color ?? AppColors.primaryTeal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryTeal))
            else
              Icon(icon, size: 22, color: primaryColor),
            const SizedBox(width: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.textPrimaryLight,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateSection() {
    return ValueListenableBuilder<UpdateManifest?>(
      valueListenable: AutoUpdater.availableUpdate,
      builder: (context, available, _) {
        if (available == null) return const SizedBox.shrink();

        final progress = AutoUpdater.progress.value;

        String label;
        IconData icon;
        VoidCallback? onTap;
        bool isLoading = false;

        if (progress == null || progress.state == UpdateState.idle) {
          label = 'UPDATE AVAILABLE — v${available.minimumVersion}';
          icon = Icons.system_update_alt_rounded;
          onTap = () {
            AutoUpdater.resetCircuitBreaker();
            AutoUpdater.checkForUpdate(available);
          };
        } else {
          switch (progress.state) {
            case UpdateState.downloading:
              final pct = (progress.fraction * 100).toStringAsFixed(0);
              label = 'DOWNLOADING... $pct%';
              icon = Icons.download_rounded;
              onTap = null;
              isLoading = true;
            case UpdateState.verifying:
              label = 'VERIFYING...';
              icon = Icons.verified_rounded;
              onTap = null;
              isLoading = true;
            case UpdateState.installing:
              label = 'INSTALLING...';
              icon = Icons.install_mobile_rounded;
              onTap = null;
              isLoading = true;
            case UpdateState.failed:
              label = 'RETRY UPDATE — v${available.minimumVersion}';
              icon = Icons.refresh_rounded;
              onTap = () {
                AutoUpdater.resetCircuitBreaker();
                AutoUpdater.checkForUpdate(available);
              };
            case UpdateState.completed:
            case UpdateState.idle:
              return const SizedBox.shrink();
          }
        }

        return Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('UPDATE'),
              const SizedBox(height: 24),
              _buildActionButton(
                icon: icon,
                label: label,
                onTap: onTap,
                color: onTap != null ? null : AppColors.textSecondaryLight,
                isLoading: isLoading,
                height: 80,
              ),
            ],
          ),
        );
      },
    );
  }
  void _startHold(String action) {
    _holdTimer?.cancel();
    _holdProgress = 0.0;
    _isHolding = true;
    _holdAction = action;
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _holdProgress += 0.04;
        if (_holdProgress >= 1.0) {
          _holdProgress = 1.0;
          _isHolding = false;
          _holdAction = null;
          timer.cancel();
          _executePowerAction(action);
        }
      });
    });
    setState(() {});
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (_isHolding) {
      setState(() {
        _isHolding = false;
        _holdProgress = 0.0;
        _holdAction = null;
      });
    }
  }

  Future<void> _executePowerAction(String action) async {
    try {
      if (action == 'shutdown') {
        await Process.run('shutdown', ['/s', '/t', '0']);
      } else if (action == 'restart') {
        await Process.run('shutdown', ['/r', '/t', '0']);
      }
    } catch (e) {
      Log.e('[Settings] Power action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Power action failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildHoldActionButton({
    required IconData icon,
    required String label,
    required String action,
    required Color color,
  }) {
    final isActive = _isHolding && _holdAction == action;
    final progress = isActive ? _holdProgress : 0.0;

    return GestureDetector(
      onTapDown: (_) => _startHold(action),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.1),
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isActive ? 0.1 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isActive)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    ),
                  Icon(
                    isActive && progress >= 1.0
                        ? icon
                        : Icons.lock_outline_rounded,
                    size: 20,
                    color: color,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
