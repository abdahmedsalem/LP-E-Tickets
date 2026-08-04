import 'package:flutter/material.dart';
import '../../core/config/app_brand_config.dart';
import '../../core/theme/app_colors.dart';

/// Icône trois flammes (charte FuelMark).
class FuelMark extends StatelessWidget {
  const FuelMark({super.key, this.size = 32});

  static const _assetPath = 'assets/images/logo_fueltoken_launcher.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.05,
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Brand logo: mark + optional wordmarks (light / dark surfaces).
class FuelLogo extends StatelessWidget {
  const FuelLogo({
    super.key,
    this.size = 22,
    this.textColor,
    this.showOrgWordmark = false,
    this.wordmarkText,
  });

  /// Mark scale
  final double size;

  /// Wordmark colour; defaults to ink on light, use white on hero blue.
  final Color? textColor;

  /// Affiche le nom opérateur à côté du pictogramme si non vide (`APP_ORG_WORDMARK`).
  final bool showOrgWordmark;

  /// Texte du wordmark ; défaut [AppBrandConfig.orgWordmark].
  final String? wordmarkText;

  @override
  Widget build(BuildContext context) {
    final c = textColor ?? AppColors.ink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FuelMark(size: size),
            if (showOrgWordmark) ...[
              if ((wordmarkText ?? AppBrandConfig.orgWordmark)
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  (wordmarkText ?? AppBrandConfig.orgWordmark).trim(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.78,
                    letterSpacing: -0.3,
                    color: c,
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}
