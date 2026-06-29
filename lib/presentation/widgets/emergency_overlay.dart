import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../services/alert_audio_service.dart';
import '../../services/notification_listener_service.dart';
import 'glass_container.dart';

class EmergencyOverlay extends StatefulWidget {
  final Widget child;
  const EmergencyOverlay({super.key, required this.child});

  @override
  State<EmergencyOverlay> createState() => _EmergencyOverlayState();
}

class _EmergencyOverlayState extends State<EmergencyOverlay>
    with TickerProviderStateMixin {
  final NotificationListenerService _notifService = NotificationListenerService();
  StreamSubscription<List<BoardNotification>>? _sub;
  StreamSubscription<BoardNotification>? _allClearSub;
  List<BoardNotification> _notifications = [];

  int _secondsRemaining = 60;
  Timer? _countdownTimer;
  bool _canDismiss = false;
  bool _showAllClearToast = false;
  Timer? _allClearToastTimer;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  late final AnimationController _scanlineCtrl;
  late final Animation<double> _scanline;

  late final AnimationController _routeDashCtrl;

  bool _wasActive = false;

  static const Color _emergencyCrimson = Color(0xFFC72C31);
  static const Color _emergencyDark = Color(0xFF8B1E22);
  BoardNotification? get _emergency =>
      _notifications.where((n) => n.priority == NotificationPriority.emergency).firstOrNull;

  int get _durationSeconds {
    final n = _emergency;
    if (n?.durationSeconds != null && n!.durationSeconds! >= 10) {
      return n.durationSeconds!;
    }
    return 60;
  }

  @override
  void initState() {
    super.initState();
    _notifications = _notifService.cachedNotifications;
    _sub = _notifService.notificationsStream.listen((list) {
      if (mounted) {
        final wasActive = _emergency != null;
        setState(() => _notifications = list);
        _onEmergencyChanged(wasActive);
      }
    });

    _allClearSub = _notifService.onAllClear.listen((_) {
      if (mounted) {
        _handleAllClear();
      }
    });

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.repeat(reverse: true);

    _scanlineCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _scanline = Tween<double>(begin: -0.05, end: 1.05).animate(
      CurvedAnimation(parent: _scanlineCtrl, curve: Curves.linear),
    );
    _scanlineCtrl.repeat();

    _routeDashCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _routeDashCtrl.repeat();

    _wasActive = _emergency != null;
    if (_wasActive) {
      _startCountdown();
      _forceWindowToFront();
    }
  }

  void _onEmergencyChanged(bool wasActive) {
    final nowActive = _emergency != null;
    if (nowActive && !wasActive) {
      _wasActive = true;
      _startCountdown();
      _forceWindowToFront();
      AlertAudioService().playAlert();
    } else if (!nowActive && _wasActive) {
      _wasActive = false;
      _resetCountdown();
      _releaseWindowFromFront();
      AlertAudioService().stopAlert();
    }
  }

  void _handleAllClear() {
    _resetCountdown();
    _releaseWindowFromFront();
    AlertAudioService().stopAlert();
    setState(() {
      _showAllClearToast = true;
    });
    _allClearToastTimer?.cancel();
    _allClearToastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showAllClearToast = false);
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = _durationSeconds;
    _canDismiss = false;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _canDismiss = true);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = _durationSeconds;
    _canDismiss = false;
  }

  Future<void> _dismiss() async {
    AlertAudioService().stopAlert();
    final n = _emergency;
    if (n != null) {
      if (n.notificationId != null && n.notificationId!.isNotEmpty) {
        await _notifService.dismissNotification(n.notificationId!);
      } else {
        _notifService.removeNotification(n.id);
      }
    }
  }

  static const _kioskChannel = MethodChannel('com.intelliattend/kiosk');

  Future<void> _forceWindowToFront() async {
    try {
      await _kioskChannel.invokeMethod('forceWindowToFront');
    } catch (_) {
      // Fallback if C++ handler isn't available
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }

  Future<void> _releaseWindowFromFront() async {
    try {
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _allClearSub?.cancel();
    _countdownTimer?.cancel();
    _allClearToastTimer?.cancel();
    _pulseCtrl.dispose();
    _scanlineCtrl.dispose();
    _routeDashCtrl.dispose();
    if (_wasActive) {
      _releaseWindowFromFront();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_emergency != null) _buildOverlay(),
        if (_showAllClearToast) _buildAllClearToast(),
      ],
    );
  }

  Widget _buildOverlay() {
    final n = _emergency!;
    final isAllClear = n.isAllClear;
    final steps = n.precautionarySteps ?? [
      'STAY CALM — Avoid panic. Breathe and focus on the exit instructions.',
      'Grab Essentials Only — Leave large items behind. Evacuate immediately.',
      'Exit via North Stairs — DO NOT USE ELEVATORS.',
      'Proceed to Assembly Point 1 — Designated parking lot area.',
    ];
    final location = n.location ?? 'Block B | Hall 402';
    final safeExit = n.safeExit ?? 'NORTH-EAST EXIT';
    final assemblyPoint = n.assemblyPoint ?? 'Main Ground Assembly';
    final nodeId = 'Node 09-X';

    final screenSize = MediaQuery.of(context).size;
    final isSmall = screenSize.width < 900;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Pulsing background
            Positioned.fill(
              child: GestureDetector(
                onTap: _canDismiss ? null : () {},
                onPanDown: _canDismiss ? null : (_) {},
                onScaleStart: _canDismiss ? null : (_) {},
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    color: Color.lerp(
                      _emergencyDark,
                      _emergencyCrimson,
                      _pulse.value,
                    ),
                  ),
                ),
              ),
            ),

            // Scanline effect
            AnimatedBuilder(
              animation: _scanline,
              builder: (_, __) => Positioned(
                top: _scanline.value * screenSize.height,
                left: 0,
                right: 0,
                height: 10,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Grid texture
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.04,
                  child: CustomPaint(
                    painter: _GridPainter(),
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Header
                    _buildHeader(n.title, isAllClear),
                    const SizedBox(height: 24),

                    // Body
                    Expanded(
                      child: isSmall
                          ? _buildSingleColumn(location, safeExit, assemblyPoint, nodeId, steps)
                          : _buildTwoColumn(location, safeExit, assemblyPoint, nodeId, steps),
                    ),
                    const SizedBox(height: 24),

                    // Bottom action bar
                    _buildBottomBar(location, nodeId, n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(String title, bool isAllClear) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
            scale: _pulse.value,
            child: child,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isAllClear ? Icons.check_circle_rounded : Icons.warning_rounded,
              size: 72,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            isAllClear ? 'ALL CLEAR' : (title.isNotEmpty ? title.toUpperCase() : 'CRITICAL EMERGENCY'),
            style: GoogleFonts.inter(
              fontSize: 96,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -4,
              height: 1.1,
            ),
            textAlign: TextAlign.start,
            softWrap: true,
          ),
        ),
      ],
    );
  }

  // ── Two-Column Layout ──

  Widget _buildTwoColumn(String location, String safeExit, String assemblyPoint, String nodeId,
      List<String> steps) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildSafetyProtocol(steps)),
        const SizedBox(width: 24),
        Expanded(child: _buildEvacuationRoute(location, safeExit, assemblyPoint)),
      ],
    );
  }

  // ── Single-Column Layout (small screens) ──

  Widget _buildSingleColumn(String location, String safeExit, String assemblyPoint, String nodeId,
      List<String> steps) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 400,
            child: _buildSafetyProtocol(steps),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 400,
            child: _buildEvacuationRoute(location, safeExit, assemblyPoint),
          ),
        ],
      ),
    );
  }

  // ── Safety Protocol Panel ──

  Widget _buildSafetyProtocol(List<String> steps) {
    return GlassContainer(
      borderRadius: 24,
      blur: 20,
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: Colors.white.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment, size: 36, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'SAFETY PROTOCOL',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final parts = _splitStep(steps[index]);
                return _buildStep(
                  number: index + 1,
                  title: parts.$1,
                  description: parts.$2,
                  highlighted: index == 2,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _splitStep(String step) {
    final dashIdx = step.indexOf('—');
    if (dashIdx == -1) {
      final colonIdx = step.indexOf(':');
      if (colonIdx == -1) return (step, '');
      return (step.substring(0, colonIdx).trim(), step.substring(colonIdx + 1).trim());
    }
    return (step.substring(0, dashIdx).trim(), step.substring(dashIdx + 1).trim());
  }

  Widget _buildStep({
    required int number,
    required String title,
    required String description,
    bool highlighted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number.toString().padLeft(2, '0'),
          style: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlighted
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.08),
                width: highlighted ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Evacuation Route Panel ──

  Widget _buildEvacuationRoute(String location, String safeExit, String assemblyPoint) {
    return GlassContainer(
      borderRadius: 24,
      blur: 20,
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: Colors.white.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map, size: 36, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'EVACUATION ROUTE',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF416900).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF416900).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE FEED',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    // Blueprint-style map background
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BlueprintPainter(),
                      ),
                    ),
                    // Route path animation
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _routeDashCtrl,
                        builder: (_, __) => CustomPaint(
                          painter: _RoutePainter(dashOffset: _routeDashCtrl.value),
                        ),
                      ),
                    ),
                    // "YOU ARE HERE" indicator
                    Positioned(
                      left: constraints.maxWidth * 0.25 - 50,
                      top: constraints.maxHeight * 0.50 - 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'YOU ARE HERE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _emergencyCrimson,
                          ),
                        ),
                      ),
                    ),
                    // "SAFE EXIT" indicator
                    Positioned(
                      right: 0,
                      top: constraints.maxHeight * 0.10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SAFE EXIT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                safeExit.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              Text(
                'DISTANCE: 145m',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom Action Bar ──

  Widget _buildBottomBar(String location, String nodeId, BoardNotification n) {
    return GlassContainer(
      borderRadius: 24,
      blur: 20,
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: Colors.white.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      width: double.infinity,
      child: Row(
        children: [
          // Location info
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'YOUR LOCATION',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  location,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.wifi_tethering, size: 14, color: Colors.white60),
                    const SizedBox(width: 6),
                    Text(
                      nodeId,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          // Countdown ring or dismiss button
          _canDismiss ? _buildDismissButton(n) : _buildCountdownRing(),

          const Spacer(),

          // Quick contacts
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'QUICK CONTACTS',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildContactButton(Icons.local_police, 'SECURITY'),
                    const SizedBox(width: 12),
                    _buildContactButton(Icons.medical_services, 'MEDICAL'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Colors.white),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Countdown Ring (replaces center of bottom bar) ──

  Widget _buildCountdownRing() {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: _secondsRemaining / _durationSeconds,
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Transform.scale(
              scale: _pulse.value,
              child: child,
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _emergencyCrimson.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.warning_rounded,
                size: 26,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            bottom: -4,
            child: Text(
              '${_secondsRemaining}s',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissButton(BoardNotification n) {
    return SizedBox(
      width: 200,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _dismiss,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: Colors.white,
          elevation: 0,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(
          n.requiresAcknowledgement ? Icons.assignment_turned_in : Icons.close,
          size: 22,
        ),
        label: Text(
          n.requiresAcknowledgement ? 'ACKNOWLEDGE' : 'DISMISS',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ── All Clear Toast ──

  Widget _buildAllClearToast() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 40,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            borderRadius: 30,
            blur: 10,
            color: const Color(0xFF1B5E20).withValues(alpha: 0.9),
            borderColor: AppColors.successLime.withValues(alpha: 0.3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.successLime.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.successLime,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'ALL CLEAR',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
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

// ── Grid Texture Painter ──

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Blueprint Background Painter ──

class _BlueprintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw some building outline rectangles
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Corridor-like rectangles
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.15, size.width * 0.25, size.height * 0.6), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.55, size.height * 0.2, size.width * 0.35, size.height * 0.55), outlinePaint);

    // Room dividers
    final roomPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 0; i < 3; i++) {
      final x = size.width * 0.12 + i * size.width * 0.07;
      canvas.drawLine(Offset(x, size.height * 0.2), Offset(x, size.height * 0.7), roomPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Route Path Painter ──

class _RoutePainter extends CustomPainter {
  final double dashOffset;

  _RoutePainter({required this.dashOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final startX = size.width * 0.35;
    final startY = size.height * 0.65;
    final midX = size.width * 0.35;
    final midY = size.height * 0.35;
    final endX = size.width * 0.75;
    final endY = size.height * 0.12;

    path.moveTo(startX, startY);
    path.lineTo(midX, midY);
    path.lineTo(endX, endY);

    // Draw the route path with animation offset
    final paint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final totalLength = metric.length;
      final drawLength = totalLength * 0.6;
      final offset = (dashOffset * totalLength) % totalLength;
      final endOffset = offset + drawLength;
      if (endOffset <= totalLength) {
        canvas.drawPath(metric.extractPath(offset, endOffset), paint);
      } else {
        canvas.drawPath(metric.extractPath(offset, totalLength), paint);
        canvas.drawPath(metric.extractPath(0, endOffset - totalLength), paint);
      }
    }

    // Draw path points
    canvas.drawCircle(Offset(startX, startY), 8, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(endX, endY), 10, Paint()..color = const Color(0xFF4ADE80));

    // Arrow at end
    final arrowPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..style = PaintingStyle.fill;
    final arrowPath = Path();
    arrowPath.moveTo(endX, endY);
    arrowPath.lineTo(endX - 12, endY - 12);
    arrowPath.lineTo(endX - 12, endY + 12);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.dashOffset != dashOffset;
}
