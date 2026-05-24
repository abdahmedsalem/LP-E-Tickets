import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Quick action: 50×50 rounded square + label below.
/// `primary: true` = elevated green box (white icon), otherwise white box.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: primary ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: primary ? null : Border.all(color: AppColors.line, width: 1),
        boxShadow: primary ? AppColors.elevatedShadow : AppColors.softShadow,
      ),
      child: Icon(
        icon,
        size: 22,
        color: primary ? Colors.white : AppColors.ink,
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            box,
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
