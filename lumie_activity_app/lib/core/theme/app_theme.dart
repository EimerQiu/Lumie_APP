import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Lumie App Theme Configuration
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primaryYellow,
      scaffoldBackgroundColor: AppColors.backgroundPaper,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryLemonDark,
        primaryContainer: AppColors.primaryLemon,
        secondary: AppColors.accentOrange,
        secondaryContainer: AppColors.accentPeach,
        surface: AppColors.backgroundWhite,
        error: AppColors.error,
        onPrimary: AppColors.textOnYellow,
        onSecondary: AppColors.textOnYellow,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 2,
        shadowColor: AppColors.primaryLemon.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLemonDark,
          foregroundColor: AppColors.textOnYellow,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.primaryLemonDark, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryLemonDark,
        foregroundColor: AppColors.textOnYellow,
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLemon),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLemon),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLemonDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundWhite,
        selectedItemColor: AppColors.primaryLemonDark,
        unselectedItemColor: AppColors.textLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedColor: AppColors.primaryLemon,
        disabledColor: AppColors.textLight.withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryLemonDark,
        linearTrackColor: AppColors.surfaceLight,
        circularTrackColor: AppColors.surfaceLight,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryLemonDark,
        inactiveTrackColor: AppColors.surfaceLight,
        thumbColor: AppColors.primaryLemonDark,
        overlayColor: AppColors.primaryLemon.withValues(alpha: 0.2),
        trackHeight: 6,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceLight,
        thickness: 1,
        space: 1,
      ),
      // Playfair Display for display/headline/title; system sans-serif for body
      textTheme: GoogleFonts.playfairDisplayTextTheme().copyWith(
        displayLarge:  GoogleFonts.playfairDisplay(fontSize: 42, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        displayMedium: GoogleFonts.playfairDisplay(fontSize: 38, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        displaySmall:  GoogleFonts.playfairDisplay(fontSize: 34, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        headlineLarge: GoogleFonts.playfairDisplay(fontSize: 30, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        headlineMedium:GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        headlineSmall: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        titleLarge:    GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        titleMedium:   GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
        titleSmall:    GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600,   color: AppColors.textPrimary),
        // Body stays in the default system sans-serif for readability
        bodyLarge:   const TextStyle(fontSize: 17, fontWeight: FontWeight.normal, color: AppColors.textPrimary),
        bodyMedium:  const TextStyle(fontSize: 15, fontWeight: FontWeight.normal, color: AppColors.textSecondary),
        bodySmall:   const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: AppColors.textLight),
        labelLarge:  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500,   color: AppColors.textPrimary),
        labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,   color: AppColors.textSecondary),
        labelSmall:  const TextStyle(fontSize: 11, fontWeight: FontWeight.w500,   color: AppColors.textLight),
      ),
    );
  }
}
