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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 70,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // Using 1-based index for student ID mapping
          final studentId = 'STU-${(index + 1).toString().padLeft(3, '0')}';
          final isPresent = verifiedIds.contains(studentId);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isPresent ? AppColors.success : Colors.transparent,
              border: Border.all(
                color: isPresent ? AppColors.success : AppColors.border,
                width: isPresent ? 0 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isPresent ? [
                BoxShadow(
                  color: AppColors.success.withOpacity(0.4),
                  blurRadius: 15,
                  spreadRadius: -2,
                )
              ] : [],
            ),
            child: Center(
              child: Text(
                (index + 1).toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isPresent ? Colors.white : AppColors.textMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
