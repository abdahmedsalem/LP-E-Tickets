import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// White surface card with a 1px line border, 16 radius and a soft shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.radius = 16,
    this.shadow = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double radius;
  final bool shadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color ?? AppColors.surface,
      border: Border.all(
        color: borderColor ?? AppColors.line,
        width: borderWidth,
      ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ? AppColors.softShadow : null,
    );

    final core = Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return core;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: core,
      ),
    );
  }
}
