import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

class PinInput extends StatelessWidget {
  final int length;
  final String value;

  const PinInput({
    super.key,
    this.length = 6,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        length,
        (index) {
          final char = index < value.length ? value[index] : '';
          final isFilled = index < value.length;
          final isFocused = index == value.length;

          return Container(
            width: 38,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 4),
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
                char,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isFilled ? AppColors.primaryTeal : (isDark ? Colors.white24 : Colors.black12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

