import 'package:flutter/material.dart';

/// Lumie App Color Palette
/// White-first design: white canvas, amber-yellow as accent
class AppColors {
  AppColors._();

  // ── Amber / Yellow accent (primary brand color) ────────────────────────────
  // Used on: buttons, progress fills, active states, highlights
  static const Color primaryLemon     = Color(0xFFFDE68A); // amber-200 — soft glow
  static const Color primaryLemonLight = Color(0xFFFFFBEB); // amber-50  — barely warm
  static const Color primaryLemonDark  = Color(0xFFF59E0B); // amber-500 — bold accent
  static const Color primaryYellow     = Color(0xFFFBBF24); // amber-400 — mid accent

  // ── Page / scaffold backgrounds ────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF9FAFB); // neutral-50 (near white)
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color surfaceLight    = Color(0xFFF3F4F6); // neutral-100 — dividers, tracks
  static const Color cardBackground  = Color(0xFFFFFFFF);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF111827); // near-black
  static const Color textSecondary = Color(0xFF6B7280); // gray-500
  static const Color textLight     = Color(0xFF9CA3AF); // gray-400
  static const Color textOnYellow  = Color(0xFF78350F); // amber-900 — on amber bg

  // ── Secondary accents ──────────────────────────────────────────────────────
  static const Color accentOrange   = Color(0xFFD97706); // amber-600
  static const Color accentPeach    = Color(0xFFFED7AA); // orange-200
  static const Color accentGreen    = Color(0xFF86EFAC); // green-300
  static const Color accentMint     = Color(0xFF99F6E4); // teal-200
  static const Color accentBlue     = Color(0xFF7DD3FC); // sky-300
  static const Color accentLavender = Color(0xFFC4B5FD); // violet-300

  // ── Intensity colours (data-viz) ───────────────────────────────────────────
  static const Color intensityLow      = Color(0xFFBBF7D0); // green-200
  static const Color intensityModerate = Color(0xFFFDE68A); // amber-200
  static const Color intensityHigh     = Color(0xFFFED7AA); // orange-200

  // ── Status colours ─────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4ADE80); // green-400
  static const Color warning = Color(0xFFFBBF24); // amber-400
  static const Color error   = Color(0xFFF87171); // red-400
  static const Color info    = Color(0xFF38BDF8); // sky-400

  // ── Ring status ────────────────────────────────────────────────────────────
  static const Color ringConnected    = Color(0xFF4ADE80);
  static const Color ringDisconnected = Color(0xFFF87171);
  static const Color ringSyncing      = Color(0xFF38BDF8);

  // ── Gradients ──────────────────────────────────────────────────────────────

  /// Page background: starts barely warm at the top, fades to pure white.
  /// Gives the sunrise hint without overwhelming the white canvas.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.25, 1.0],
    colors: [
      Color(0xFFFFFBEB), // amber-50 — just a whisper of warmth
      Color(0xFFFAFAFA), // near white
      Color(0xFFFFFFFF), // pure white
    ],
  );

  /// Card background: pure white. Shadow gives the elevation.
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  /// Progress / game bar fill: vibrant amber streak.
  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFDE68A), Color(0xFFFBBF24), Color(0xFFF59E0B)],
  );

  /// Used on icon containers, bottom-nav selected state, chips.
  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)], // amber-100 → amber-200
  );

  /// Cool (blue) gradient for ring/sync elements.
  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFF7DD3FC)],
  );

  /// Mint gradient for health data sections.
  static const LinearGradient mintGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFCCFBF1), Color(0xFF99F6E4), Color(0xFF5EEAD4)],
  );

  /// Sunrise: used for the logo / brand icon container.
  static const LinearGradient sunriseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFBBF24)],
  );

  /// Activity ring arc gradient.
  static const LinearGradient activityRingGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  /// Radial gradient for circular progress (inner glow).
  static const RadialGradient circularProgressGradient = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  );

  // ── Convenience shadow ─────────────────────────────────────────────────────
  /// Neutral card shadow — no yellow tint, just depth.
  static List<BoxShadow> get cardShadow => [
        const BoxShadow(
          color: Color(0x0D000000), // 5% black
          blurRadius: 16,
          spreadRadius: 0,
          offset: Offset(0, 2),
        ),
        const BoxShadow(
          color: Color(0x08000000), // 3% black — secondary soft edge
          blurRadius: 4,
          spreadRadius: 0,
          offset: Offset(0, 1),
        ),
      ];
}
