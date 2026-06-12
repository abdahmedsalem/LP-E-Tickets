import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

class AmountInline extends StatelessWidget {
  const AmountInline({
    super.key,
    required this.amount,
    required this.valueStyle,
    this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  static const double unitFontSize = 9.5;

  final int amount;
  final TextStyle valueStyle;
  final TextStyle? unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final resolvedUnitStyle = (unitStyle ?? const TextStyle()).copyWith(
      fontSize: unitFontSize,
      fontWeight: unitStyle?.fontWeight ?? FontWeight.w700,
      color:
          unitStyle?.color ??
          valueStyle.color ??
          DefaultTextStyle.of(context).style.color ??
          AppColors.ink,
      height: unitStyle?.height,
      letterSpacing: unitStyle?.letterSpacing,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
          TextSpan(text: ' MRU', style: resolvedUnitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
