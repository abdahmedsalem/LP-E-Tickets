import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Empty state widget designed to be responsive on small heights/widths.
/// Wraps content in a scroll view with width cap to avoid overflows.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxContentWidth = constraints.maxWidth.clamp(0.0, 480.0);
        final bool compact =
            constraints.maxHeight != double.infinity &&
            constraints.maxHeight < 260;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, compact ? 16 : 28, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight == double.infinity
                  ? 0
                  : constraints.maxHeight,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.leaderGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 34, color: AppColors.leaderGreen),
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.ink,
                        fontSize: compact ? 20 : 24,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 20),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _EmptyFolderPainter extends CustomPainter {
  const _EmptyFolderPainter({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 260;
    final top = size.height * 0.14;
    final stroke = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final blackFill = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.fill;
    final mutedFill = Paint()
      ..color = const Color(0xFFE6E7E9)
      ..style = PaintingStyle.fill;
    final whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final accentFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(58 * scale, top, 118 * scale, 96 * scale),
      Radius.circular(11 * scale),
    );
    canvas.drawRRect(back, blackFill);

    for (var i = 0; i < 4; i++) {
      final y = top + (9 + i * 23) * scale;
      final row = RRect.fromRectAndRadius(
        Rect.fromLTWH(72 * scale, y, 148 * scale, 20 * scale),
        Radius.circular(5 * scale),
      );
      canvas.drawRRect(row, whiteFill);
      if (i == 0) {
        canvas.drawCircle(
          Offset(83 * scale, y + 10 * scale),
          7 * scale,
          accentFill,
        );
        _drawSmallCheck(canvas, Offset(83 * scale, y + 10 * scale), scale);
      } else {
        canvas.drawCircle(
          Offset(83 * scale, y + 10 * scale),
          7 * scale,
          mutedFill,
        );
      }
      canvas.drawRRect(row, stroke);
      canvas.drawLine(
        Offset(100 * scale, y + 7 * scale),
        Offset((i == 0 ? 160 : 182) * scale, y + 7 * scale),
        Paint()
          ..color = const Color(0xFFC9CDD2)
          ..strokeWidth = 3 * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    final folder = Path()
      ..moveTo(78 * scale, top + 62 * scale)
      ..lineTo(228 * scale, top + 62 * scale)
      ..quadraticBezierTo(
        242 * scale,
        top + 62 * scale,
        237 * scale,
        top + 77 * scale,
      )
      ..lineTo(216 * scale, top + 130 * scale)
      ..quadraticBezierTo(
        211 * scale,
        top + 143 * scale,
        196 * scale,
        top + 143 * scale,
      )
      ..lineTo(68 * scale, top + 143 * scale)
      ..quadraticBezierTo(
        53 * scale,
        top + 143 * scale,
        58 * scale,
        top + 128 * scale,
      )
      ..lineTo(73 * scale, top + 77 * scale)
      ..quadraticBezierTo(
        76 * scale,
        top + 62 * scale,
        78 * scale,
        top + 62 * scale,
      )
      ..close();
    canvas.drawPath(folder, accentFill);
    canvas.drawPath(folder, stroke);

    final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(188 * scale, top + 80 * scale, 44 * scale, 16 * scale),
      Radius.circular(8 * scale),
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * scale,
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 18 * scale,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(canvas, Offset(202 * scale, top + 79 * scale));
  }

  void _drawSmallCheck(Canvas canvas, Offset center, double scale) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(center.dx - 3.5 * scale, center.dy)
      ..lineTo(center.dx - 0.8 * scale, center.dy + 3 * scale)
      ..lineTo(center.dx + 4 * scale, center.dy - 4 * scale);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EmptyFolderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.icon != icon;
  }
}
