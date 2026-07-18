import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../core/theme/app_theme.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../services/hydration_service.dart';
import '../../services/timetable_cache.dart';
import '../../services/network_info_service.dart';

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
  String _sectionName = '';
  Timer? _speedTimer;
  int _speedTestMs = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startNetworkMonitoring();
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _speedTimer?.cancel();
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
    _resolveSectionName();
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

  void _resolveSectionName() {
    try {
      final cache = TimetableCache();
      final current = cache.currentSlot;
      if (current != null && current.sectionName.isNotEmpty) {
        _sectionName = current.sectionName;
      } else {
        final isar = Isar.getInstance();
        if (isar != null) {
          final all = isar.timetableEntrys.where().findAllSync();
          if (all.isNotEmpty) {
            _sectionName = all.first.sectionName;
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      Log.d('[Settings] Could not resolve section: $e');
    }
  }

  String get _hotspotName {
    final section = _sectionName.isNotEmpty ? _sectionName : 'BOARD';
    return '$section Wi-Fi';
  }

  String get _hotspotPassword {
    final room = _profile?.roomNumber ?? _registration?.roomName ?? '0000';
    return 'IntelliAttend@$room';
  }

  Future<void> _runSpeedTest() async {
    setState(() => _speedTestMs = -1);
    final probe = await Future(() async {
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect('1.1.1.1', 443,
            timeout: const Duration(seconds: 3));
        await socket.close();
        sw.stop();
        return sw.elapsedMilliseconds;
      } catch (_) {
        return 0;
      }
    });
    if (mounted) setState(() => _speedTestMs = probe);
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

        _resolveSectionName();

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
                    _buildActionButton(
                      icon: Icons.sync_rounded,
                      label: 'SYNC TIMETABLE',
                      onTap: _isSyncing ? null : _handleSyncTimetable,
                      isLoading: _isSyncing,
                      height: 80,
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
                  _wifiIcon(info),
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
                      '${info.connectionType} • ${info.speedLabel}',
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
              _buildMetricItem(
                Icons.signal_cellular_alt_rounded,
                'Status',
                info.isConnected
                    ? (hasInternet ? 'Online' : 'Offline')
                    : 'Disconnected',
              ),
              const Spacer(),
              _buildSpeedTestButton(),
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

  Widget _buildSpeedTestButton() {
    final isTesting = _speedTestMs == -1;
    return InkWell(
      onTap: isTesting ? null : _runSpeedTest,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.2)),
        ),
        child: isTesting
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryTeal))
            : Text(
                _speedTestMs > 0 ? 'Speed: ${_speedTestMs}ms' : 'Test Speed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryTeal,
                ),
              ),
      ),
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
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.black.withValues(alpha: 0.05), height: 1),
          const SizedBox(height: 16),
          _buildHotspotInfoRow('Network Name', _hotspotName, Icons.wifi_rounded),
          const SizedBox(height: 12),
          _buildHotspotInfoRow('Password', _hotspotPassword, Icons.lock_outline_rounded),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primaryTeal),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enable Windows Mobile Hotspot with these credentials so students can connect and access the internet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotspotInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryTeal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight)),
              const SizedBox(height: 2),
              Text(
                value,
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
          icon: const Icon(Icons.copy_rounded, size: 18),
          color: AppColors.textSecondaryLight,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied'),
                duration: const Duration(seconds: 1),
                backgroundColor: AppColors.primaryTeal,
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _wifiIcon(NetworkInfo info) {
    if (!info.isConnected) return Icons.wifi_off_rounded;
    if (!info.hasInternet) return Icons.wifi_rounded;
    if (info.latencyMs < 50) return Icons.signal_cellular_alt_rounded;
    if (info.latencyMs < 150) return Icons.signal_cellular_alt_2_bar_rounded;
    return Icons.signal_cellular_alt_1_bar_rounded;
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
}
