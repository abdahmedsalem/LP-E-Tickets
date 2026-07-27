import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

abstract final class ConfirmationLineStyles {
  static const title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.15,
  );

  static const amountValue = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: Color(0xFF2E7D32),
  );

  static final amountUnit = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
  );
}
