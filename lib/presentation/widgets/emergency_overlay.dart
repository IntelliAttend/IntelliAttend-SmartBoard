import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/notification_listener_service.dart';

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
  List<BoardNotification> _notifications = [];

  late final AnimationController _pulseBgCtrl;
  late final Animation<double> _pulseBg;

  late final AnimationController _iconCtrl;
  late final Animation<double> _iconScale;

  late final AnimationController _scanlineCtrl;
  late final Animation<double> _scanlinePos;

  bool _wasActive = false;

  BoardNotification? get _emergency =>
      _notifications.where((n) => n.priority == NotificationPriority.emergency).firstOrNull;

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

    _pulseBgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _pulseBg = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulseBgCtrl, curve: Curves.easeInOut),
    );
    _pulseBgCtrl.repeat(reverse: true);

    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _iconScale = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.easeInOut),
    );
    _iconCtrl.repeat(reverse: true);

    _scanlineCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _scanlinePos = Tween<double>(begin: -0.05, end: 1.0).animate(
      CurvedAnimation(parent: _scanlineCtrl, curve: Curves.linear),
    );
    _scanlineCtrl.repeat();
  }

  void _onEmergencyChanged(bool wasActive) {
    final nowActive = _emergency != null;
    if (nowActive && !wasActive) {
      _wasActive = true;
      _setAlwaysOnTop(true);
    } else if (!nowActive && _wasActive) {
      _wasActive = false;
      _setAlwaysOnTop(false);
    }
  }

  void _setAlwaysOnTop(bool onTop) {
    try {
      windowManager.setAlwaysOnTop(onTop);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseBgCtrl.dispose();
    _iconCtrl.dispose();
    _scanlineCtrl.dispose();
    if (_wasActive) {
      _setAlwaysOnTop(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_emergency != null) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    return AnimatedBuilder(
      animation: _pulseBg,
      builder: (context, _) {
        final color = Color.lerp(
          const Color(0xFFC72C31),
          const Color(0xFF8B1E22),
          _pulseBg.value,
        );
        return Positioned.fill(
          child: Material(
            color: color,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GridPainter(),
                    child: const SizedBox.expand(),
                  ),
                ),
                AnimatedBuilder(
                  animation: _scanlinePos,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(0, _scanlinePos.value * MediaQuery.of(context).size.height),
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.06),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        Expanded(child: _buildContentGrid()),
                        const SizedBox(height: 24),
                        _buildBottomBar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _iconScale,
          builder: (context, _) {
            return Transform.scale(
              scale: _iconScale.value,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_rounded, size: 80, color: Colors.white),
              ),
            );
          },
        ),
        const SizedBox(width: 24),
        Flexible(
          child: Text(
            'CRITICAL\nEMERGENCY',
            style: GoogleFonts.inter(
              fontSize: MediaQuery.of(context).size.width > 1200 ? 96 : 64,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.04,
              height: 1.1,
              color: Colors.white,
              shadows: [
                Shadow(
                  offset: const Offset(2, 2),
                  blurRadius: 0,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
        ),
        if (_emergency != null && _emergency!.id.startsWith('debug-'))
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: SizedBox(
              width: 120,
              height: 48,
              child: TextButton.icon(
                onPressed: () => _notifService.removeNotification(_emergency!.id),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
                icon: const Icon(Icons.close, size: 20),
                label: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContentGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return Row(
            children: [
              Expanded(child: _buildSafetyProtocol()),
              const SizedBox(width: 24),
              Expanded(child: _buildEvacuationRoute()),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 400, child: _buildSafetyProtocol()),
              const SizedBox(height: 24),
              SizedBox(height: 400, child: _buildEvacuationRoute()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSafetyProtocol() {
    final steps = _emergency!.precautionarySteps ?? [];
    return _buildGlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, size: 36, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'SAFETY PROTOCOL',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.01,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Expanded(
              child: steps.isEmpty
                  ? Center(
                      child: Text(
                        'Follow emergency evacuation procedures immediately.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 18),
                      ),
                    )
                  : ListView.separated(
                      itemCount: steps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final step = steps[index];
                        final parts = step.split(' — ');
                        final title = parts.isNotEmpty ? parts[0] : '';
                        final desc = parts.length > 1 ? parts.sublist(1).join(' — ') : '';
                        final isLast = index == steps.length - 1;
                        return _buildStepCard(
                          number: '0${index + 1}',
                          title: title,
                          description: desc,
                          highlight: isLast,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String number,
    required String title,
    required String description,
    bool highlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: highlight ? 1.0 : 0.4),
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
                color: highlight
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
                width: highlight ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 15,
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

  Widget _buildEvacuationRoute() {
    final n = _emergency!;
    return _buildGlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map_outlined, size: 36, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'EVACUATION ROUTE',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.01,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                _buildLiveBadge(),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.15,
                              child: Container(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RoutePainter(),
                            ),
                          ),
                          Positioned(
                            left: w * 0.35 - 44,
                            top: h * 0.65 - 10,
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
                                  color: const Color(0xFFC72C31),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: w * 0.7 - 34,
                            top: h * 0.15 - 14,
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
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  n.safeExit != null
                      ? '${n.safeExit!.toUpperCase()} CORRIDOR'
                      : 'NORTH-EAST CORRIDOR',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  'DISTANCE: 145m',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF416900).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF416900).withValues(alpha: 0.3)),
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
          const SizedBox(width: 8),
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
    );
  }

  Widget _buildBottomBar() {
    final n = _emergency!;
    return _buildGlassPanel(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'YOUR LOCATION',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.location ?? 'Block B',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.wifi_tethering, size: 14, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        'Node 09-X',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QUICK CONTACTS',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildContactButton(Icons.local_police_outlined, 'SECURITY'),
                    const SizedBox(width: 12),
                    _buildContactButton(Icons.medical_services_outlined, 'MEDICAL'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

  Widget _buildGlassPanel({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 50,
                offset: const Offset(0, 25),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final pathPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(w * 0.35, h * 0.65)
      ..lineTo(w * 0.35, h * 0.35)
      ..lineTo(w * 0.7, h * 0.35)
      ..lineTo(w * 0.7, h * 0.15);

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + 12).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), pathPaint);
        distance += 22;
      }
    }

    canvas.drawCircle(
      Offset(w * 0.35, h * 0.65),
      7,
      Paint()..color = Colors.white,
    );

    final exitPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(
      Offset(w * 0.7, h * 0.15),
      10,
      exitPaint,
    );
    canvas.drawCircle(
      Offset(w * 0.7, h * 0.15),
      7,
      Paint()..color = const Color(0xFF4ADE80),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
