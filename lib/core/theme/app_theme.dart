
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // PRD Palette - IntelliAttend Professional & Dark Logic
  static const Color primaryTeal = Color(0xFF14B8A6);
  static const Color successLime = Color(0xFF84CC16);
  static const Color warningAmber = Color(0xFFF59E0B);
  
  // Backgrounds
  static const Color bgDark = Color(0xFF050505);      // Deep Black
  static const Color surfaceDark = Color(0xFF1E1E1E); // Charcoal
  static const Color bgLight = Color(0xFFF8FAFC);     // Crisp Off-White
  static const Color surfaceLight = Colors.white;
  
  // Text Colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // Legacy/Helper mappings (keeping some for compatibility if needed)
  static const Color background = bgDark;
  static const Color surface = surfaceDark;
  static const Color primary = primaryTeal;
  static const Color textPrimary = textPrimaryDark;
  static const Color textMuted = textSecondaryDark;
  static const Color textSlate = textSecondaryDark;
  static const Color success = successLime;
  static const Color error = Color(0xFFEF4444);
  static const Color glassBackground = Color(0x0DFFFFFF); 
  static const Color glassBorder = Color(0x1AFFFFFF);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        surface: AppColors.surfaceLight,
        onSurface: AppColors.textPrimaryLight,
        primary: AppColors.primaryTeal,
        onPrimary: Colors.white,
        secondary: AppColors.bgLight,
        onSecondary: AppColors.textPrimaryLight,
        error: Color(0xFFEF4444),
      ),
      scaffoldBackgroundColor: AppColors.bgLight,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(AppColors.textPrimaryLight, AppColors.textSecondaryLight),
      elevatedButtonTheme: _buildButtonTheme(AppColors.primaryTeal, Colors.white),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.bgDark,
        onSurface: AppColors.textPrimaryDark,
        primary: AppColors.primaryTeal,
        onPrimary: Colors.white,
        secondary: AppColors.surfaceDark,
        onSecondary: AppColors.textPrimaryDark,
        error: Color(0xFFEF4444),
      ),
      scaffoldBackgroundColor: AppColors.bgDark,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(AppColors.textPrimaryDark, AppColors.textSecondaryDark),
      elevatedButtonTheme: _buildButtonTheme(AppColors.primaryTeal, Colors.white),
    );
  }

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: GoogleFonts.inter(fontSize: 84, fontWeight: FontWeight.w900, color: primary, letterSpacing: -2),
      displayMedium: GoogleFonts.inter(fontSize: 56, fontWeight: FontWeight.w800, color: primary, letterSpacing: -1),
      displaySmall: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, color: primary),
      headlineLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: primary),
      headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: primary),
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: secondary),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: primary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: secondary),
      labelLarge: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: secondary, letterSpacing: 2),
    );
  }

  static ElevatedButtonThemeData _buildButtonTheme(Color bg, Color fg) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
        elevation: 0,
      ),
    );
  }
}

