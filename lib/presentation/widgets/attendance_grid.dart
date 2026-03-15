
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 60,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        final studentId = 'STU-${(index + 1).toString().padLeft(3, '0')}';
        final isPresent = verifiedIds.contains(studentId);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            color: isPresent ? AppColors.success.withOpacity(0.2) : Colors.transparent,
            border: Border.all(
              color: isPresent ? AppColors.success : AppColors.border,
              width: isPresent ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              (index + 1).toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPresent ? AppColors.success : AppColors.textMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}
