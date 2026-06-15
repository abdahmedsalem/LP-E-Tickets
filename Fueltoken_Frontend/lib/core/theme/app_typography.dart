import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// FuelToken typography helpers.
///
/// We use **Poppins** for the main UI (Latin/French), **Noto Sans Arabic** when
/// the locale is Arabic, and **JetBrains Mono** for codes / monetary values.
class AppTypography {
  AppTypography._();

  /// Poppins base text style. Use this for body / heading text.
  static TextStyle inter({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// JetBrains Mono — for codes, references and currency amounts.
  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      letterSpacing: letterSpacing,
    );
  }

  /// Arabic fallback for places where we know the string is Arabic.
  static TextStyle arabic({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.notoSansArabic(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      height: height,
    );
  }

  /// Title eyebrow (uppercase 11px, muted, tracked).
  static TextStyle eyebrow({Color? color}) => inter(
    size: 11,
    weight: FontWeight.w700,
    color: color ?? AppColors.muted,
    letterSpacing: 0.6,
  );
}
