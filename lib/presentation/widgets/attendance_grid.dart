import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/screen_utils.dart';
import '../../core/utils/roll_number_utils.dart';
import 'glass_container.dart';

class AttendanceGrid extends StatelessWidget {
  final List<String> verifiedIds;
  final int totalCount;
  final List<String>? rollNumbers;

  const AttendanceGrid({
    super.key,
    required this.verifiedIds,
    required this.totalCount,
    this.rollNumbers,
  });

  @override
  Widget build(BuildContext context) {
    ScreenUtils.init(context);

    final rollNums = rollNumbers ??
        RollNumberUtils.generateRollNumbers(totalCount);

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: ScreenUtils.gridDelegate(capacity: totalCount),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        final displayRoll = index < rollNums.length
            ? rollNums[index]
            : RollNumberUtils.generateSeatCode(index);
        final isPresent = verifiedIds.contains(displayRoll);

        return GlassContainer(
          borderRadius: ScreenUtils.radius(12),
          color: isPresent ? AppColors.success.withValues(alpha: 0.2) : null,
          borderColor: isPresent ? AppColors.success.withValues(alpha: 0.5) : null,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                displayRoll,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: ScreenUtils.clampedSp(14, min: 8, max: 20),
                  color: isPresent ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
