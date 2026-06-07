import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/qr_token.dart';
import '../../data/models/purchase_lot.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  factory StatusBadge.qr(QrState state) {
    switch (state) {
      case QrState.active:
        return StatusBadge(
          label: state.label,
          background: AppColors.successSurface,
          foreground: AppColors.success,
          icon: Icons.check_circle_outline,
        );
      case QrState.blocked:
        return StatusBadge(
          label: state.label,
          background: AppColors.warningSurface,
          foreground: AppColors.warning,
          icon: Icons.block,
        );
      case QrState.consumed:
        return StatusBadge(
          label: state.label,
          background: AppColors.surfaceAlt,
          foreground: AppColors.textSecondary,
          icon: Icons.local_gas_station_outlined,
        );
      case QrState.expired:
        return StatusBadge(
          label: state.label,
          background: AppColors.dangerSurface,
          foreground: AppColors.danger,
          icon: Icons.schedule,
        );
    }
  }

  factory StatusBadge.lot(PurchaseLotState state) {
    switch (state) {
      case PurchaseLotState.draft:
        return StatusBadge(
          label: state.label,
          background: AppColors.surfaceAlt,
          foreground: AppColors.textSecondary,
          icon: Icons.edit_note,
        );
      case PurchaseLotState.submitted:
        return StatusBadge(
          label: state.label,
          background: AppColors.infoSurface,
          foreground: AppColors.info,
          icon: Icons.hourglass_top,
        );
      case PurchaseLotState.approved:
        return StatusBadge(
          label: state.label,
          background: AppColors.successSurface,
          foreground: AppColors.success,
          icon: Icons.verified_outlined,
        );
      case PurchaseLotState.rejected:
        return StatusBadge(
          label: state.label,
          background: AppColors.dangerSurface,
          foreground: AppColors.danger,
          icon: Icons.cancel_outlined,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
