import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'glass_container.dart';

class AttendanceGrid extends StatelessWidget {
  final List<String> verifiedIds;
  final int totalCount;

  const AttendanceGrid({
    super.key, 
    required this.verifiedIds, 
    required this.totalCount
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 80,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        final studentId = 'STU-${(index + 1).toString().padLeft(3, '0')}';
        final isPresent = verifiedIds.contains(studentId);

        return GlassContainer(
          borderRadius: 12,
          color: isPresent ? AppColors.success.withValues(alpha: 0.2) : null,
          borderColor: isPresent ? AppColors.success.withValues(alpha: 0.5) : null,
          child: Center(
            child: Text(
              (index + 1).toString(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: isPresent ? AppColors.success : AppColors.textMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}
