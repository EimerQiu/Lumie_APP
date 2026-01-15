import 'package:flutter/material.dart';

/// Lumie App Color Palette
/// Primary theme: Light/Lemon Yellow with gradients
class AppColors {
  AppColors._();

  // Primary Lemon Yellow Colors
  static const Color primaryLemon = Color(0xFFFFF59D);
  static const Color primaryLemonLight = Color(0xFFFFFDE7);
  static const Color primaryLemonDark = Color(0xFFFFEB3B);
  static const Color primaryYellow = Color(0xFFFFEE58);

  // Gradient Colors
  static const Color gradientStart = Color(0xFFFFFDE7);
  static const Color gradientMiddle = Color(0xFFFFF59D);
  static const Color gradientEnd = Color(0xFFFFEB3B);

  // Secondary Accent Colors (complementary)
  static const Color accentOrange = Color(0xFFFFB74D);
  static const Color accentPeach = Color(0xFFFFCC80);
  static const Color accentGreen = Color(0xFFA5D6A7);
  static const Color accentMint = Color(0xFFB2DFDB);
  static const Color accentBlue = Color(0xFF81D4FA);
  static const Color accentLavender = Color(0xFFB39DDB);

  // Intensity Colors (Teen-safe categorical)
  static const Color intensityLow = Color(0xFFC8E6C9);
  static const Color intensityModerate = Color(0xFFFFF59D);
  static const Color intensityHigh = Color(0xFFFFCC80);

  // Status Colors
  static const Color success = Color(0xFF81C784);
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFE57373);
  static const Color info = Color(0xFF64B5F6);

  // Neutral Colors
  static const Color backgroundLight = Color(0xFFFFFDE7);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFFFF9C4);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Text Colors
  static const Color textPrimary = Color(0xFF424242);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textLight = Color(0xFF9E9E9E);
  static const Color textOnYellow = Color(0xFF5D4037);

  // Ring Status Colors
  static const Color ringConnected = Color(0xFF81C784);
  static const Color ringDisconnected = Color(0xFFE57373);
  static const Color ringSyncing = Color(0xFF64B5F6);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMiddle, gradientEnd],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFDE7)],
  );

  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryLemonLight, primaryLemon, primaryLemonDark],
  );

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFE082)],
  );

  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
  );

  static const LinearGradient mintGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0F2F1), Color(0xFFB2DFDB), Color(0xFF80CBC4)],
  );

  static const LinearGradient sunriseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFCC80), Color(0xFFFFB74D)],
  );

  static const LinearGradient activityRingGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFEB3B), Color(0xFFFFC107), Color(0xFFFF9800)],
  );

  // Radial Gradients for circular progress
  static const RadialGradient circularProgressGradient = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [primaryLemon, primaryLemonDark],
  );
}
