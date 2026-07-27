import 'package:flutter/material.dart';

/// Jetons de couleur de l’app (#0D6FCB splash, Inter) et palette FuelMark.
class AppColors {
  AppColors._();

  // ── Primaire « fintech » (#0D6FCB et déclinaisons) ──
  static const Color brandBlue = Color(0xFF0D6FCB);
  static const Color brandBlueMid = Color(0xFF0B63B8);
  static const Color brandBlueDeep = Color(0xFF074A93);
  static const Color brandBlueSoft = Color(0xFFE8F4FC);
  static const Color brandBlueTint = Color(0xFFF5F9FF);

  /// Accent (violet).
  static const Color accentViolet = Color(0xFF7C3AED);
  static const Color accentVioletSoft = Color(0xFFF3EEFF);

  /// Teal pour cartes hero
  static const Color accentTeal = Color(0xFF0E7C66);

  /// App Material primary — electric blue CTAs / links / nav
  static const Color primary = brandBlue;

  /// Deeper blues for typography on light surfaces
  static const Color primaryDark = brandBlueDeep;
  static const Color primaryDeep = brandBlueDeep;
  static const Color primarySoft = brandBlueSoft;
  static const Color primaryTint = brandBlueTint;

  /// Back-compat (older widgets)
  static const Color primaryLight = Color(0xFF56A6F5);
  static const Color primarySurface = brandBlueSoft;

  // Couleurs du pictogramme trois flammes (FuelMark)
  static const Color leaderGreen = Color(0xFF2EA043);
  static const Color leaderGreenDark = Color(0xFF1F7A33);
  static const Color brandRed = Color(0xFFE53935);
  static const Color brandRedSoft = Color(0xFFFDECEA);
  static const Color brandYellow = Color(0xFFF9C81E);
  static const Color brandYellowSoft = Color(0xFFFEF7DC);

  static const Color brandRedSurface = brandRedSoft;
  static const Color accent = brandYellow;
  static const Color accentSurface = brandYellowSoft;

  // ── Neutrals ──
  static const Color ink = Color(0xFF0B1220);
  static const Color ink2 = Color(0xFF1E293B);
  static const Color body = Color(0xFF475569);
  static const Color muted = Color(0xFF64748B);
  static const Color hint = Color(0xFF94A3B8);
  static const Color line = Color(0xFFE2E8F0);
  static const Color lineSoft = Color(0xFFF1F5F9);

  /// Fond principal — teinte verte discrète (parcours client & coquilles).
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = lineSoft;

  // ── Semantic ──
  static const Color success = leaderGreen;
  static const Color successSurface = Color(0xFFE8F5EC);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSurface = Color(0xFFFFF7E6);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSurface = Color(0xFFFEE2E2);

  /// Info aligns with UI blue family
  static const Color info = brandBlueMid;
  static const Color infoSurface = brandBlueSoft;

  // ── Text aliases ──
  static const Color textPrimary = ink;
  static const Color textSecondary = body;
  static const Color textMuted = muted;
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = line;
  static const Color divider = lineSoft;

  // ── Gradients ──
  /// Splash — dominance verte FuelMark.
  static const Gradient splashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [leaderGreenDark, leaderGreen, Color(0xFF0B63B8)],
    stops: [0.0, 0.52, 1.0],
  );

  static const Gradient loginHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14532D), leaderGreen, Color(0xFF34D399)],
    stops: [0.0, 0.48, 1.0],
  );

  /// Bouton principal (connexion, CTA auth).
  static const Gradient clientCtaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [leaderGreenDark, leaderGreen],
  );

  /// Wallet — blue → teal with depth (premium card)
  static const Gradient walletGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlueDeep, brandBlue, accentTeal],
    stops: [0.05, 0.55, 1.0],
  );

  static const Gradient violetEdgeGradient = LinearGradient(
    colors: [accentViolet, Color(0xFF5B21B6)],
  );

  /// Face value badges (golden chip)
  static const Gradient yellowChipGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDE68A), brandYellow, Color(0xFFF59E0B)],
    stops: [0.0, 0.45, 1.0],
  );

  /// Scan OK / « valide » banner (success read)
  static const Gradient validGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [leaderGreenDark, leaderGreen, accentTeal],
    stops: [0.0, 0.55, 1.0],
  );

  /// Accueil client — carte solde (vert, proche du mock « Fuel »)
  static const Gradient clientHomeWalletGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF065F46), leaderGreen, Color(0xFF34D399)],
    stops: [0.0, 0.48, 1.0],
  );

  // ── Shadows (blue-tinted glow) ──
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x080D2040),
      blurRadius: 8,
      offset: Offset(0, 3),
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> elevatedShadow = const [
    BoxShadow(
      color: Color(0x330D6FCB),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 10),
    ),
  ];

  static List<BoxShadow> walletGlowShadow = const [
    BoxShadow(
      color: Color(0x550D6FCB),
      blurRadius: 28,
      spreadRadius: -8,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x220E7C66),
      blurRadius: 40,
      spreadRadius: -12,
      offset: Offset(0, 20),
    ),
  ];
}
