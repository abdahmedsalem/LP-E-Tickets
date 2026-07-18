import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import 'amount_inline.dart';
import 'single_line_card_title.dart';

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
        Row(
          children: [
            Expanded(
              child: SingleLineCardTitle(
                text: title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: AmountInline(amount: amount),
            ),
          ],
        ),
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
