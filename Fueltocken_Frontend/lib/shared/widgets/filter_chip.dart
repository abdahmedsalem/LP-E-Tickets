import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Pill filter chip — dark ink when active, white otherwise.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
    this.count,
    this.leadingDotColor,
    this.compact = false,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final int? count;
  final Color? leadingDotColor;

  /// Padding and type size réduits pour barres de filtres horizontales.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.body;
    final bg = active ? AppColors.ink : AppColors.surface;
    final hPad = compact ? 9.0 : 14.0;
    final vPad = compact ? 5.0 : 7.0;
    final fontSize = compact ? 11.0 : 12.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: active ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingDotColor != null) ...[
              Container(
                width: compact ? 5 : 6,
                height: compact ? 5 : 6,
                decoration: BoxDecoration(color: leadingDotColor, shape: BoxShape.circle),
              ),
              SizedBox(width: compact ? 5 : 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (count != null) ...[
              SizedBox(width: compact ? 3 : 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: active ? 0.7 : 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
