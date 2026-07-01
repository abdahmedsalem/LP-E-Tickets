import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'screen_header.dart';

class StandardConfirmationScaffold extends StatelessWidget {
  const StandardConfirmationScaffold({
    super.key,
    required this.title,
    required this.introText,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    required this.onBack,
    required this.content,
    this.confirming = false,
    this.confirmIcon = Icons.check_circle_outline_rounded,
    this.confirmIconSize = 19,
    this.topSpacing = 14,
  });

  final String title;
  final String introText;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onBack;
  final List<Widget> content;
  final bool confirming;
  final IconData confirmIcon;
  final double confirmIconSize;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: confirming ? null : onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF43A047,
                    ).withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              confirmIcon,
                              color: Colors.white,
                              size: confirmIconSize,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              confirmLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: confirming ? null : onCancel,
                  child: const Text(
                    'Annuler',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: title, onBack: onBack),
            SizedBox(height: topSpacing),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  Text(
                    introText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...content,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
