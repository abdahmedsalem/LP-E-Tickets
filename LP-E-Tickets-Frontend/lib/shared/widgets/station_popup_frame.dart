import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class StationPopupFrame extends StatelessWidget {
  const StationPopupFrame({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.iconBackgroundColor,
    required this.actionLabel,
    required this.onAction,
    this.accentGradient,
    this.content,
    this.maxHeightFactor = 0.84,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;
  final Color iconBackgroundColor;
  final Gradient? accentGradient;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget? content;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 390, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.16),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: accentGradient == null ? accentColor : null,
                      gradient: accentGradient,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: iconBackgroundColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.18),
                              width: 5,
                            ),
                          ),
                          child: Icon(icon, size: 42, color: accentColor),
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
                        const SizedBox(height: 8),
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
                        if (content != null) ...[
                          const SizedBox(height: 22),
                          content!,
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: onAction,
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
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
      ),
    );
  }
}
