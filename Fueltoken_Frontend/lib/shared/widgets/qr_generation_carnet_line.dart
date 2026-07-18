import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import 'confirmation_line_main_row.dart';

class QrGenerationCarnetLine extends StatelessWidget {
  const QrGenerationCarnetLine({
    super.key,
    required this.title,
    required this.amount,
    required this.expirationDate,
  });

  final String title;
  final int amount;
  final DateTime expirationDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfirmationLineMainRow(title: title, amount: amount),
        const SizedBox(height: 8),
        Text(
          l10n.expiresOn(Formatters.dateTimeDash(expirationDate)),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}
