import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A card widget with gradient background.
///
/// Set [glass] to render a frosted-glass version instead — the gradient is
/// dropped, the page background is blurred behind the card, and a faint
/// white tint + 1-px white border keep content legible. Used on the Today
/// page so the dynamic sky bleeds through every card.
class GradientCard extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  /// Opacity applied to gradient colors only (0.0–1.0). Content stays fully opaque.
  final double opacity;
  /// When true, render as a glassmorphic card (transparent + backdrop blur +
  /// subtle border). [gradient] and [opacity] are ignored.
  final bool glass;

  const GradientCard({
    super.key,
    required this.child,
    this.gradient,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.onTap,
    this.opacity = 1.0,
    this.glass = false,
  });

  Gradient _applyOpacity(Gradient g) {
    if (opacity >= 1.0) return g;
    if (g is LinearGradient) {
      return LinearGradient(
        begin: g.begin,
        end: g.end,
        colors: g.colors.map((c) => c.withValues(alpha: opacity)).toList(),
        stops: g.stops,
        tileMode: g.tileMode,
      );
    }
    return g;
  }

  @override
  Widget build(BuildContext context) {
    if (glass) return _buildGlass();

    final effectiveGradient = _applyOpacity(gradient ?? AppColors.cardGradient);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: effectiveGradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Frosted-glass card. Each card is its own self-contained floating surface
  /// — semi-transparent pale-gold fill, soft backdrop blur, warm 1-px border,
  /// and a 2-layer shadow so the card visibly lifts off the sky background.
  ///
  /// Designed for the Today page: every card is rendered independently so the
  /// dynamic sky shows through the gaps between them (Oura-style), instead of
  /// stacking inside one shared glass panel.
  Widget _buildGlass() {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          // Tight contact shadow — defines the bottom edge against the sky.
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
          // Lift shadow — gives the card a visible elevation so each one
          // feels independent rather than welded to the cards above and below.
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              // Pale-gold tint — keeps the sky visible while staying in the
              // app's amber palette.
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x66FFFFFF), // 40% white
                  Color(0x4DFEF3C7), // 30% amber-100
                ],
              ),
              border: Border.all(
                // Warm-tinted highlight rather than pure white — reads as
                // gold-on-sky and matches the activity ring's hue.
                color: const Color(0x80FEF3C7),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gradient button with customizable gradient
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final IconData? icon;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.gradient,
    this.borderRadius = 12,
    this.padding,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? (gradient ?? AppColors.progressGradient)
            : LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade400],
              ),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: AppColors.primaryLemonDark.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnYellow,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.textOnYellow, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          color: AppColors.textOnYellow,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
