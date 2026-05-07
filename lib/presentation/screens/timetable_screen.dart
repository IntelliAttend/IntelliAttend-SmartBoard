import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/isar_schemas.dart';

class TimetableScreen extends StatelessWidget {
  final List<TimetableEntry> weeklyTimeline;
  
  const TimetableScreen({super.key, required this.weeklyTimeline});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final currentDayIdx = DateTime.now().weekday - 1;

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
            tabs: days.map((day) => Tab(text: day.toUpperCase())).toList(),
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
      final isSunday = weeklyTimeline.any((e) => e.dayOfWeek == 7) ? false : true; // This is a bit naive, let's just check the index if possible
      // Actually, we can check the tab index or the day of week.
      // But entries are already filtered by day.
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
            if (DateTime.now().weekday == DateTime.sunday) ...[
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

    return ListView.separated(
      padding: const EdgeInsets.all(40),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final now = DateTime.now();
        final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        final isLive = entry.startTime.compareTo(timeStr) <= 0 && entry.endTime.compareTo(timeStr) > 0 && entry.dayOfWeek == now.weekday;

        return Container(
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
              Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.2)),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.courseName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
        );
      },
    );
  }
}
