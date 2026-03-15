
import 'package:flutter/material.dart';

class AppColors {
  // Deep Academic Palette
  static const Color background = Color(0xFF0F172A); // Deep Navy
  static const Color surface = Color(0xFF1E293B);    // Slate Blue
  static const Color primary = Color(0xFF38BDF8);    // Sky Blue
  
  // High-Contrast Text
  static const Color textPrimary = Color(0xFFF8FAF6);
  static const Color textMuted = Color(0xFF94A3B8);
  
  // Status Colors (Muted, not Neon)
  static const Color success = Color(0xFF10B981);    // Emerald
  static const Color error = Color(0xFFEF4444);      // Rose
  static const Color warning = Color(0xFFF59E0B);    // Amber
  
  static const Color border = Color(0xFF334155);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      fontFamily: 'Inter', // High-legibility sans-serif
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textMuted),
      ),
    );
  }
}
