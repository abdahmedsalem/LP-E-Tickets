import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

class AmountInline extends StatelessWidget {
  const AmountInline({
    super.key,
    required this.amount,
    this.valueStyle,
    this.unitStyle,
    this.currency,
    this.textAlign = TextAlign.left,
  });

  static const double unitFontSize = 9.5;

  final int amount;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final String? currency;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final fallbackUnitColor = const Color(0xFF2E7D32).withValues(alpha: 0.82);
    final resolvedValueStyle =
        valueStyle ??
        TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF2E7D32),
        );
    final resolvedUnitStyle =
        (unitStyle ??
                TextStyle(
                  fontSize: unitFontSize,
                  fontWeight: FontWeight.w700,
                  color: fallbackUnitColor,
                ))
            .copyWith(
              fontSize: unitFontSize,
              fontWeight: unitStyle?.fontWeight ?? FontWeight.w700,
              color: unitStyle?.color ?? fallbackUnitColor,
              height: unitStyle?.height,
              letterSpacing: unitStyle?.letterSpacing,
            );

    final unit = Formatters.currencyOrDefault(currency);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: Formatters.numberFr(amount),
            style: resolvedValueStyle,
          ),
          TextSpan(text: ' $unit', style: resolvedUnitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
