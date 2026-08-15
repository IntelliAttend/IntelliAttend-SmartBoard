import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/isar_schemas.dart';
import '../../services/time_sync_service.dart';

class TimetableScreen extends StatelessWidget {
  final List<TimetableEntry> weeklyTimeline;
  
  const TimetableScreen({super.key, required this.weeklyTimeline});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentDayIdx = TimeSyncService.timeNow.weekday - 1;

    return DefaultTabController(
      length: 7,
      initialIndex: currentDayIdx,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: AppBar(
          title: const Text('Weekly Timetable', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primaryTeal,
            labelColor: AppColors.primaryTeal,
            unselectedLabelColor: Colors.grey,
            tabs: dayNames.map((day) => Tab(text: day.toUpperCase())).toList(),
          ),
        ),
        body: TabBarView(
          children: List.generate(7, (index) {
            final dayEntries = weeklyTimeline.where((e) => e.dayOfWeek == (index + 1)).toList();
            return _buildDayView(context, dayEntries, isDark);
          }),
        ),
      ),
    );
  }

  Widget _buildDayView(BuildContext context, List<TimetableEntry> entries, bool isDark) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy_outlined, 
              size: 64, 
              color: isDark ? Colors.white10 : Colors.black12
            ),
            const SizedBox(height: 16),
            Text(
              'NO CLASSES SCHEDULED',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (TimeSyncService.timeNow.weekday == DateTime.sunday) ...[
              const SizedBox(height: 8),
              const Text(
                'SUNDAY FUNDAY',
                style: TextStyle(
                  color: AppColors.primaryTeal,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 4,
                ),
              ),
            ]
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(40),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final now = TimeSyncService.timeNow;
        final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        final isLive = entry.startTime.compareTo(timeStr) <= 0 && entry.endTime.compareTo(timeStr) > 0 && entry.dayOfWeek == now.weekday;

        // Use explicit is_break flag from server instead of inferring from time gaps
        if (entry.isBreak) {
          return _buildBreakCard(entry, isDark);
        }

        // Check if there's a break before this entry (using explicit flag)
        final hasBreakBefore = index > 0 && entries[index - 1].isBreak;

        return Column(
          children: [
            if (hasBreakBefore) ...[
              const SizedBox(height: 8),
            ] else if (index > 0) ...[
              const SizedBox(height: 16),
            ],
            Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive ? AppColors.primaryTeal.withValues(alpha: 0.3) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              width: isLive ? 2 : 1,
            ),
            boxShadow: isLive ? [BoxShadow(color: AppColors.primaryTeal.withValues(alpha: 0.1), blurRadius: 10)] : [],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.startTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(entry.endTime, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Container(width: 1, height: 60, color: Colors.grey.withValues(alpha: 0.2)),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.subjectCode.isNotEmpty)
                      Text(
                        entry.subjectCode,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(entry.courseName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(
                      (entry.facultyName.contains('@') ? entry.facultyName.split('@')[0].replaceAll('_', ' ').toUpperCase() : entry.facultyName.toUpperCase()),
                      style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)
                    ),
                  ],
                ),
              ),
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
            ],
          ),
        ),
          ],
        );
      },
    );
  }

  /// Build a break card with explicit break information from the server.
  Widget _buildBreakCard(TimetableEntry entry, bool isDark) {
    final breakName = entry.periodName ?? 'Break';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.startTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                Text(
                  entry.endTime,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.coffee_outlined,
                    size: 14,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    breakName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
