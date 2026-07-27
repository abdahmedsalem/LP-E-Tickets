import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'station_popup_frame.dart';

class StationQrFailureDialog extends StatelessWidget {
  const StationQrFailureDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onClose,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return StationPopupFrame(
      title: title,
      message: message,
      icon: Icons.close_rounded,
      accentColor: AppColors.danger,
      iconBackgroundColor: AppColors.dangerSurface,
      actionLabel: actionLabel,
      onAction: onClose,
      maxHeightFactor: 0.82,
    );
  }
}
