import 'package:flutter/material.dart';
import '../../models/isar_schemas.dart';
import '../../core/theme/app_theme.dart';

class TimelineSlot extends StatelessWidget {
  final TimetableEntry entry;
  final bool isLive;
  final bool isCompleted;
  final bool isFailed;

  const TimelineSlot({
    super.key,
    required this.entry,
    this.isLive = false,
    this.isCompleted = false,
    this.isFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isLive 
        ? AppColors.primaryTeal 
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isLive 
            ? AppColors.primaryTeal.withValues(alpha: 0.05) 
            : Colors.transparent,
        border: isLive
            ? Border(top: BorderSide(color: AppColors.primaryTeal, width: 2))
            : isFailed
                ? Border(top: BorderSide(color: AppColors.warningAmber, width: 2))
                : isCompleted
                    ? Border(top: BorderSide(color: AppColors.successLime, width: 2))
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
          const SizedBox(height: 4),
          Text(
            "${entry.startTime} – ${entry.endTime}",
            style: TextStyle(
              color: isLive ? color : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.courseName,
            style: TextStyle(
              color: isLive ? color.withValues(alpha: 0.7) : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
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

}

