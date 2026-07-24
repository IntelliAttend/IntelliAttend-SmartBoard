import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/lifecycle/lifecycle_phase.dart';
import '../../core/recovery/recovery_manager.dart';
import '../../core/recovery/recovery_state.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryScreen
//
// Full-screen recovery UI shown when the application fails to start.
// Replaces the bare-bones InitFailureScreen with a themed, diagnostic-rich
// interface that guides the user through recovery.
//
// The screen is a standalone MaterialApp (same pattern as InitFailureScreen)
// because it runs BEFORE the main app lifecycle completes.
//
// Design principles:
//   - Dark theme (consistent with update overlay)
//   - Deterministic progress (no spinners without context)
//   - Plain-language explanations
//   - Diagnostic details visible but not overwhelming
//   - Action buttons clearly communicate safety level
// ─────────────────────────────────────────────────────────────────────────────
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _RecoveryScaffold(),
    );
  }
}

class _RecoveryScaffold extends StatefulWidget {
  const _RecoveryScaffold();

  @override
  State<_RecoveryScaffold> createState() => _RecoveryScaffoldState();
}

class _RecoveryScaffoldState extends State<_RecoveryScaffold>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: ValueListenableBuilder<RecoveryState>(
        valueListenable: RecoveryManager.stateNotifier,
        builder: (context, state, _) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 48),
                        _buildIcon(state),
                        const SizedBox(height: 28),
                        _buildTitle(state),
                        const SizedBox(height: 12),
                        _buildSubtitle(state),
                        const SizedBox(height: 8),
                        _buildStatusMessage(state),
                        const SizedBox(height: 28),
                        _buildDiagnosticsPanel(state),
                        if (state.diagnostics.timings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildTimingsPanel(state),
                        ],
                        const SizedBox(height: 32),
                        _buildActions(state),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Icon ────────────────────────────────────────────────────────────────

  Widget _buildIcon(RecoveryState state) {
    final color = state.isResolving
        ? AppColors.primaryTeal
        : state.isTransitioning
            ? AppColors.successLime
            : AppColors.error;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = state.isResolving
            ? 0.6 + (_pulseController.value * 0.4)
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: Icon(
            _iconForType(state.type),
            size: 72,
            color: color,
          ),
        );
      },
    );
  }

  IconData _iconForType(RecoveryType type) {
    switch (type) {
      case RecoveryType.crashLoop:
        return Icons.restart_alt_rounded;
      case RecoveryType.integrityFailure:
        return Icons.shield_rounded;
      case RecoveryType.lifecycleFailure:
        return Icons.error_outline_rounded;
      case RecoveryType.startupTimeout:
        return Icons.timer_off_rounded;
      case RecoveryType.updateCorruption:
        return Icons.system_update_rounded;
      case RecoveryType.unhandledError:
        return Icons.bug_report_rounded;
    }
  }

  // ── Text ────────────────────────────────────────────────────────────────

  Widget _buildTitle(RecoveryState state) {
    String text;
    switch (state.type) {
      case RecoveryType.crashLoop:
        text = 'Startup Crash Detected';
        break;
      case RecoveryType.integrityFailure:
        text = 'Integrity Check Failed';
        break;
      case RecoveryType.lifecycleFailure:
        text = 'Initialization Error';
        break;
      case RecoveryType.startupTimeout:
        text = 'Startup Timed Out';
        break;
      case RecoveryType.updateCorruption:
        text = 'Update Recovery';
        break;
      case RecoveryType.unhandledError:
        text = 'Unexpected Error';
        break;
    }

    return Text(
      text,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryDark,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle(RecoveryState state) {
    final parts = <String>[];
    if (state.diagnostics.appVersion != null) {
      parts.add('v${state.diagnostics.appVersion}');
    }
    if (state.diagnostics.crashCount != null && state.diagnostics.crashCount! > 0) {
      parts.add('${state.diagnostics.crashCount} consecutive failures');
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textSecondaryDark,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildStatusMessage(RecoveryState state) {
    if (state.statusMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: state.isResolving
            ? AppColors.primaryTeal.withValues(alpha: 0.1)
            : state.isTransitioning
                ? AppColors.successLime.withValues(alpha: 0.1)
                : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state.isResolving
              ? AppColors.primaryTeal.withValues(alpha: 0.3)
              : state.isTransitioning
                  ? AppColors.successLime.withValues(alpha: 0.3)
                  : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isResolving) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryTeal,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              state.statusMessage!,
              style: TextStyle(
                fontSize: 13,
                color: state.isResolving
                    ? AppColors.primaryTeal
                    : state.isTransitioning
                        ? AppColors.successLime
                        : AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Diagnostics Panel ──────────────────────────────────────────────────

  Widget _buildDiagnosticsPanel(RecoveryState state) {
    final d = state.diagnostics;
    final rows = <_DiagnosticRow>[];

    if (d.failedPhase != null) {
      rows.add(_DiagnosticRow('Failed Phase', d.failedPhase!.name));
    }
    if (d.errorMessage != null && d.errorMessage!.isNotEmpty) {
      rows.add(_DiagnosticRow('Error', d.errorMessage!));
    }
    if (d.appVersion != null) {
      rows.add(_DiagnosticRow('Version', d.appVersion!));
    }
    if (d.crashCount != null) {
      rows.add(_DiagnosticRow('Crash Count', '${d.crashCount}'));
    }
    if (d.isAutoStart) {
      rows.add(_DiagnosticRow('Launch Type', 'Auto-start'));
    }
    if (d.elapsedMs != null) {
      rows.add(_DiagnosticRow('Elapsed', '${d.elapsedMs}ms'));
    }
    for (final entry in d.extra.entries) {
      rows.add(_DiagnosticRow(entry.key, entry.value));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return AnimatedCrossFade(
      firstChild: _buildDiagnosticsCollapsed(rows.length),
      secondChild: _buildDiagnosticsExpanded(rows),
      crossFadeState: _showDetails
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
    );
  }

  Widget _buildDiagnosticsCollapsed(int fieldCount) {
    return GestureDetector(
      onTap: () => setState(() => _showDetails = true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 14,
              color: AppColors.textSecondaryDark,
            ),
            const SizedBox(width: 8),
            Text(
              'Show Diagnostic Details ($fieldCount fields)',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 14,
              color: AppColors.textSecondaryDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsExpanded(List<_DiagnosticRow> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showDetails = false),
            child: Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 14,
                  color: AppColors.textSecondaryDark,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Diagnostic Details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_less,
                  size: 14,
                  color: AppColors.textSecondaryDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _buildDiagnosticRow(rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(_DiagnosticRow row) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            row.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryDark,
            ),
          ),
        ),
        Expanded(
          child: Text(
            row.value,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textPrimaryDark,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ── Phase Timings Panel ────────────────────────────────────────────────

  Widget _buildTimingsPanel(RecoveryState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 14,
                color: AppColors.textSecondaryDark,
              ),
              const SizedBox(width: 8),
              const Text(
                'Phase Timings',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final timing in state.diagnostics.timings) ...[
            if (timing != state.diagnostics.timings.first)
              const SizedBox(height: 4),
            _buildTimingRow(timing, state),
          ],
        ],
      ),
    );
  }

  Widget _buildTimingRow(PhaseTiming timing, RecoveryState state) {
    final failed = timing.phase == state.diagnostics.failedPhase;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            timing.phase.name,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: failed
                  ? AppColors.error
                  : AppColors.textSecondaryDark,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${timing.duration.inMilliseconds}ms',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: failed
                  ? AppColors.error
                  : AppColors.textPrimaryDark,
            ),
          ),
        ),
        if (failed)
          const Icon(Icons.close_rounded, size: 12, color: AppColors.error)
        else
          const Icon(Icons.check_rounded, size: 12, color: AppColors.successLime),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Widget _buildActions(RecoveryState state) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        if (!state.isTransitioning) ...[
          // Retry button
          _ActionButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            color: AppColors.primaryTeal,
            enabled: state.awaitingUserAction,
            onPressed: () => RecoveryManager.retry(),
          ),
          // Launch Anyway button (crash loop only)
          if (state.canLaunchAnyway)
            _ActionButton(
              label: 'Launch Anyway',
              icon: Icons.play_arrow_rounded,
              color: AppColors.warningAmber,
              enabled: state.awaitingUserAction,
              onPressed: () => RecoveryManager.launchAnyway(),
            ),
          // Close button
          _ActionButton(
            label: 'Close Application',
            icon: Icons.close_rounded,
            color: AppColors.error,
            enabled: state.awaitingUserAction,
            onPressed: () async {
              RecoveryManager.close();
              await windowManager.destroy();
            },
          ),
        ] else if (state.isResolving || state.phase == RecoveryPhase.resolved) ...[
          // Show progress while transitioning
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryTeal,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Helper classes ────────────────────────────────────────────────────────

class _DiagnosticRow {
  final String label;
  final String value;
  const _DiagnosticRow(this.label, this.value);
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.enabled = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.3),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
    );
  }
}
