import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Uppercase tracked eyebrow used above each section card group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.color});

  final String text;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: color ?? AppColors.muted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
