import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 38×38 square icon button (white surface, soft border).
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.badge,
    this.size = 38,
    this.iconSize = 18,
    this.background,
    this.iconColor,

    /// When true, no inner stroke — for grouped toolbars with outer frame.
    this.borderless = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final int? badge;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? iconColor;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: background ?? AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: borderless
                    ? null
                    : BoxDecoration(
                        border: Border.all(color: AppColors.line, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? AppColors.ink,
                ),
              ),
            ),
          ),
          if (badge != null && badge! > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandRed,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    badge!.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
