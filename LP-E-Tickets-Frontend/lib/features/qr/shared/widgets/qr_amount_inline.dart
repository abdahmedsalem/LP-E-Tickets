import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

/// Consistent amount-and-currency treatment shared by QR confirmation screens.
class QrAmountInline extends StatelessWidget {
  const QrAmountInline({
    super.key,
    required this.amount,
    required this.valueStyle,
    required this.unitStyle,
    this.textAlign = TextAlign.start,
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
        TextSpan(text: ' ${Formatters.defaultCurrency}', style: unitStyle),
      ],
    ),
    textAlign: textAlign,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
