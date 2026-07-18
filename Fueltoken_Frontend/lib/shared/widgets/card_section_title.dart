import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class CardSectionTitle extends StatelessWidget {
  const CardSectionTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
  }
}
