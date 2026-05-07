import 'package:flutter/material.dart';
import '../../models/isar_schemas.dart';
import '../../core/theme/app_theme.dart';

class TimelineSlot extends StatelessWidget {
  final TimetableEntry entry;
  final bool isLive;

  const TimelineSlot({
    super.key,
    required this.entry,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isLive 
        ? AppColors.primaryTeal 
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      decoration: BoxDecoration(
        color: isLive 
            ? AppColors.primaryTeal.withValues(alpha: 0.05) 
            : Colors.transparent,
        border: isLive 
            ? Border(top: BorderSide(color: AppColors.primaryTeal, width: 2)) 
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.successLime,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Icon(
            _getIconForCourse(entry.courseName),
            color: color,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            isLive ? "${entry.startTime} (LIVE)" : entry.startTime,
            style: TextStyle(
              color: isLive ? color : const Color(0xFF0F172A), // slate-900
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.courseName,
            style: TextStyle(
              color: isLive ? color.withValues(alpha: 0.7) : const Color(0xFF64748B), // slate-500
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _getIconForCourse(String name) {
    name = name.toLowerCase();
    if (name.contains('data structures')) return Icons.sensors;
    if (name.contains('algorithm')) return Icons.code;
    if (name.contains('math')) return Icons.functions;
    if (name.contains('science')) return Icons.science;
    if (name.contains('history')) return Icons.history_edu;
    return Icons.schedule;
  }
}

