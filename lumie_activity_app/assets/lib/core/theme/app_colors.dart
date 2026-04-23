import 'package:flutter/material.dart';

/// Lumie App — warm-neutral palette.
/// White/paper canvas · amber-gold accent · clean grays.
class AppColors {
  AppColors._();

  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color backgroundPaper = Color(0xFFFDFCF8); // warm off-white
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF5F3EE); // warm off-white surface
  static const Color surfaceLight    = Color(0xFFE8E6E1); // warm divider / track
  static const Color cardBackground  = Color(0xFFFFFFFF);

  // ── Amber accent ───────────────────────────────────────────────────────────
  static const Color primaryLemonDark  = Color(0xFFF59E0B); // amber-500 — CTA, progress
  static const Color primaryYellow     = Color(0xFFFBBF24); // amber-400
  static const Color primaryLemon      = Color(0xFFFEF3C7); // amber-100 — chip bg
  static const Color primaryLemonLight = Color(0xFFFFFBEB); // amber-50  — very subtle

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1C1917); // warm near-black
  static const Color textSecondary = Color(0xFF78716C); // stone-500
  static const Color textLight     = Color(0xFFA8A29E); // stone-400
  static const Color textOnYellow  = Color(0xFF78350F); // amber-900 on amber bg

  // ── Status (minimal set) ───────────────────────────────────────────────────
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFF59E0B); // reuse accent
  static const Color error   = Color(0xFFF87171);
  static const Color info    = Color(0xFF38BDF8);

  // ── Ring status ────────────────────────────────────────────────────────────
  static const Color ringConnected    = Color(0xFF4ADE80);
  static const Color ringDisconnected = Color(0xFFF87171);
  static const Color ringSyncing      = Color(0xFF38BDF8);

  // ── Intensity (data-viz only) ──────────────────────────────────────────────
  static const Color intensityLow      = Color(0xFFBBF7D0);
  static const Color intensityModerate = Color(0xFFFDE68A);
  static const Color intensityHigh     = Color(0xFFFED7AA);

  // ── Accent aliases kept for compatibility ──────────────────────────────────
  static const Color accentOrange   = Color(0xFFD97706); // amber-600
  static const Color accentPeach    = Color(0xFFFEF3C7); // → same as primaryLemon
  static const Color accentGreen    = Color(0xFF86EFAC);
  static const Color accentMint     = Color(0xFF99F6E4);
  static const Color accentBlue     = Color(0xFF7DD3FC);
  static const Color accentLavender = Color(0xFFC4B5FD);

  // ── Gradients ──────────────────────────────────────────────────────────────

  /// Page background — warm paper, no dramatic colour shift.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFDFCF8), Color(0xFFFDFCF8)],
  );

  /// Card — pure white, shadow does the work.
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  /// Amber streak — for progress bars, game bar fill.
  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  /// Warm amber — chips, icon containers, nav selected state.
  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
  );

  /// Cool blue — ring/sync elements.
  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFF7DD3FC)],
  );

  /// Teal — health/wellness data sections.
  static const LinearGradient mintGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFCCFBF1), Color(0xFF99F6E4), Color(0xFF5EEAD4)],
  );

  /// Brand logo container.
  static const LinearGradient sunriseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFBBF24)],
  );

  /// Activity ring arc.
  static const LinearGradient activityRingGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  static const RadialGradient circularProgressGradient = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  );

  // ── Neutral card shadow ────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x0D000000), blurRadius: 16, offset: Offset(0, 2)),
        BoxShadow(color: Color(0x08000000), blurRadius: 4,  offset: Offset(0, 1)),
      ];
}
