import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/glass_container.dart';

class PreparingScreen extends StatelessWidget {
  final String courseName;
  final String facultyName;
  final String? sectionId;
  final String roomName;
  final String? startTime;

  const PreparingScreen({
    super.key,
    required this.courseName,
    required this.facultyName,
    required this.roomName,
    this.sectionId,
    this.startTime,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      body: Stack(
        children: [
          Opacity(
            opacity: isDark ? 0.05 : 0.03,
            child: Center(
              child: Image.asset(
                'assets/background.png',
                width: size.width * 0.6,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassContainer(
                  width: 500,
                  padding: const EdgeInsets.all(48),
                  borderRadius: 32,
                  color: isDark
                      ? AppColors.surfaceDark.withValues(alpha: 0.9)
                      : Colors.white,
                  borderColor: AppColors.primaryTeal.withValues(alpha: 0.3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school_outlined,
                          color: AppColors.primaryTeal,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        courseName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline,
                              size: 18, color: isDark ? Colors.white54 : Colors.black54),
                          const SizedBox(width: 8),
                          Text(
                            facultyName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                      if (sectionId != null && sectionId!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_outlined,
                                size: 16, color: isDark ? Colors.white38 : Colors.black38),
                            const SizedBox(width: 8),
                            Text(
                              'Section: $sectionId',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.meeting_room_outlined,
                              size: 16, color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(width: 8),
                          Text(
                            roomName,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                      if (startTime != null && startTime!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.schedule_outlined,
                                size: 16, color: isDark ? Colors.white38 : Colors.black38),
                            const SizedBox(width: 8),
                            Text(
                              'Start: $startTime',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.warningAmber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: AppColors.warningAmber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.warningAmber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'FACULTY PREPARING ATTENDANCE',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warningAmber,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primaryTeal,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'WAITING FOR FACULTY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
