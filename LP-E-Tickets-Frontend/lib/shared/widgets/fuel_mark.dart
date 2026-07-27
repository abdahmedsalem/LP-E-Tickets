import 'package:flutter/material.dart';
import '../../core/config/app_brand_config.dart';
import '../../core/theme/app_colors.dart';

/// Icône trois flammes (charte FuelMark).
class FuelMark extends StatelessWidget {
  const FuelMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.05,
      child: CustomPaint(painter: _FuelMarkPainter()),
    );
  }
}

class _FuelMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Source viewBox is 32 × 34.
    final scaleX = size.width / 32.0;
    final scaleY = size.height / 34.0;
    canvas.scale(scaleX, scaleY);

    void path(Path Function() build, Color color) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawPath(build(), paint);
    }

    // Green flame
    path(() {
      final p = Path();
      p.moveTo(9, 33);
      p.cubicTo(2, 28, 1, 19, 7, 12);
      p.cubicTo(11, 7, 12, 4, 11, 1);
      p.cubicTo(16, 5, 18, 11, 16, 18);
      p.cubicTo(15, 22, 13, 26, 13, 30);
      p.cubicTo(13, 32, 11, 33, 9, 33);
      p.close();
      return p;
    }, AppColors.leaderGreen);

    // Red flame
    path(() {
      final p = Path();
      p.moveTo(19, 33);
      p.cubicTo(12, 30, 9, 22, 14, 15);
      p.cubicTo(17, 11, 18, 8, 17, 4);
      p.cubicTo(22, 8, 25, 14, 23, 21);
      p.cubicTo(22, 25, 21, 28, 22, 31);
      p.cubicTo(22, 32.5, 20.5, 33, 19, 33);
      p.close();
      return p;
    }, AppColors.brandRed);

    // Yellow drop
    path(() {
      final p = Path();
      p.moveTo(22, 33);
      p.cubicTo(17, 32, 16, 26, 19, 22);
      p.cubicTo(21, 19, 22, 17, 22, 15);
      p.cubicTo(25, 18, 27, 23, 26, 28);
      p.cubicTo(25.5, 31, 24, 33, 22, 33);
      p.close();
      return p;
    }, AppColors.brandYellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
