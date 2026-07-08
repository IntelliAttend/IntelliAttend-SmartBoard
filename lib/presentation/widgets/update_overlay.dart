import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auto_updater.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateOverlay
//
// Full-screen overlay that displays during a binary update. It is mounted in
// the widget tree via the [IntelliAttendApp] builder (see main.dart) and
// listens to [AutoUpdater.progress] via a [ValueListenableBuilder].
//
// When [AutoUpdater.progress] is `null` the overlay is invisible and passes
// through its child widget. When non-null it renders a blurred backdrop with
// a progress indicator, version info, and status text.
//
// ── Visual design ───────────────────────────────────────────────────────────
// Matches the dark, professional aesthetic of the existing overlays
// (shutdown_countdown_overlay, emergency_overlay) — blurred background, grid
// pattern, teal accent color.
// ─────────────────────────────────────────────────────────────────────────────
class UpdateOverlay extends StatelessWidget {
  final Widget child;
  const UpdateOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateProgress?>(
      valueListenable: AutoUpdater.progress,
      builder: (context, progress, _) {
        if (progress == null || progress.state == UpdateState.idle) {
          return child;
        }
        return _buildOverlay(context, progress);
      },
    );
  }

  Widget _buildOverlay(BuildContext context, UpdateProgress progress) {
    final isError = progress.state == UpdateState.failed;
    final isComplete = progress.state == UpdateState.completed;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Blurred backdrop.
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      color: AppColors.bgDark.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                // Grid pattern.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.025,
                      child: CustomPaint(
                        painter: _GridPainter(),
                      ),
                    ),
                  ),
                ),
                // Content.
                SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildIcon(progress),
                        const SizedBox(height: 24),
                        _buildTitle(progress),
                        const SizedBox(height: 12),
                        _buildStatusText(progress),
                        const SizedBox(height: 32),
                        if (!isError && !isComplete)
                          _buildProgressIndicator(progress),
                        if (isError) _buildErrorFooter(context, progress),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Icon (varies by state) ────────────────────────────────────────────────

  Widget _buildIcon(UpdateProgress progress) {
    switch (progress.state) {
      case UpdateState.downloading:
      case UpdateState.verifying:
      case UpdateState.installing:
        return SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            backgroundColor: AppColors.primaryTeal.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
          ),
        );
      case UpdateState.completed:
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.successLime.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.successLime.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: AppColors.successLime,
          ),
        );
      case UpdateState.failed:
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.error_rounded,
            size: 48,
            color: AppColors.error,
          ),
        );
      case UpdateState.idle:
        return const SizedBox.shrink();
    }
  }

  // ── Title ──────────────────────────────────────────────────────────────────

  Widget _buildTitle(UpdateProgress progress) {
    String title;
    Color color;
    switch (progress.state) {
      case UpdateState.downloading:
      case UpdateState.verifying:
      case UpdateState.installing:
        title = 'Updating SmartBoard';
        color = Colors.white;
      case UpdateState.completed:
        title = 'Update Complete';
        color = AppColors.successLime;
      case UpdateState.failed:
        title = 'Update Failed';
        color = AppColors.error;
      case UpdateState.idle:
        return const SizedBox.shrink();
    }

    return Text(
      title,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      ),
    );
  }

  // ── Status text ────────────────────────────────────────────────────────────

  Widget _buildStatusText(UpdateProgress progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        progress.statusText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          color: Colors.white.withValues(alpha: 0.6),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  // ── Progress bar (determinate during download, indeterminate during verify) ─

  Widget _buildProgressIndicator(UpdateProgress progress) {
    if (progress.state == UpdateState.downloading) {
      // fraction > 0 = determinate, fraction == -1 = indeterminate (unknown size)
      final isDeterminate = progress.fraction > 0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: isDeterminate ? progress.fraction : null,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
          ),
        ),
      );
    }

    // Indeterminate state (verifying / installing).
    return const SizedBox(
      width: 200,
      child: LinearProgressIndicator(
        minHeight: 4,
        backgroundColor: Color(0x14FFFFFF),
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
      ),
    );
  }

  // ── Error footer (shown when state == UpdateState.failed) ──────────────────

  Widget _buildErrorFooter(BuildContext context, UpdateProgress progress) {
    final isForced = progress.force;

    return Column(
      children: [
        if (progress.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              progress.error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.error.withValues(alpha: 0.8),
              ),
            ),
          ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () {
            AutoUpdater.progress.value = null; // dismiss overlay
          },
          child: const Text(
            'Dismiss',
            style: TextStyle(color: AppColors.primaryTeal),
          ),
        ),
        if (isForced)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This update is required. The board will retry automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Grid pattern (matches shutdown_countdown_overlay) ───────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;

    const spacing = 60.0;
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
