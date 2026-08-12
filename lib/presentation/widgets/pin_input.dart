import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

class PinInput extends StatelessWidget {
  final int length;
  final String value;
  final bool obscureText;
  final double? availableWidth;

  const PinInput({
    super.key,
    this.length = 4,
    required this.value,
    this.obscureText = false,
    this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double maxWidth = availableWidth ?? 220;
    final double spacing = maxWidth < 200 ? 3.0 : 4.0;
    final double boxWidth =
        ((maxWidth - (length * 2 * spacing)) / length).clamp(28.0, 52.0);
    final double boxHeight = (boxWidth * 1.37).clamp(38.0, 70.0);
    final double charFontSize = (boxWidth * 0.52).clamp(14.0, 22.0);
    final double dotFontSize = (boxWidth * 0.32).clamp(8.0, 14.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        length,
        (index) {
          final char = index < value.length ? value[index] : '';
          final isFilled = index < value.length;
          final isFocused = index == value.length;

          return Container(
            width: boxWidth,
            height: boxHeight,
            margin: EdgeInsets.symmetric(horizontal: spacing),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppColors.bgLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isFocused
                    ? AppColors.primaryTeal
                    : (isDark ? Colors.white10 : Colors.black12),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                obscureText && isFilled ? '●' : char,
                style: GoogleFonts.jetBrainsMono(
                  fontSize:
                      obscureText && isFilled ? dotFontSize : charFontSize,
                  fontWeight: FontWeight.bold,
                  color: isFilled
                      ? AppColors.primaryTeal
                      : (isDark ? Colors.white24 : Colors.black12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
