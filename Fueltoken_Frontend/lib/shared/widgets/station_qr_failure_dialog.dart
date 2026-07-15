import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 390, maxHeight: maxHeight),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 7, color: AppColors.danger),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: AppColors.dangerSurface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.16),
                            width: 5,
                          ),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 42,
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.35,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: onClose,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            actionLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
