import 'package:flutter/material.dart';

import 'amount_inline.dart';
import 'confirmation_line_styles.dart';
import 'quantity_circle_badge.dart';
import 'single_line_card_title.dart';

class ConfirmationLineMainRow extends StatelessWidget {
  const ConfirmationLineMainRow({
    super.key,
    required this.title,
    required this.amount,
    this.currency,
    this.quantity,
    this.showQuantity = false,
  });

  static const double height = 20;

  final String title;
  final int amount;
  final String? currency;
  final int? quantity;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 8,
          child: SizedBox(
            height: height,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleLineCardTitle(
                text: title,
                style: ConfirmationLineStyles.title,
              ),
            ),
          ),
        ),
        if (showQuantity)
          Expanded(
            flex: 2,
            child: SizedBox(
              height: height,
              child: Center(
                child: QuantityCircleBadge(
                  quantity: quantity ?? 0,
                  size: height,
                ),
              ),
            ),
          ),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: height,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AmountInline(
                amount: amount,
                currency: currency,
                textAlign: TextAlign.end,
                valueStyle: ConfirmationLineStyles.amountValue,
                unitStyle: ConfirmationLineStyles.amountUnit,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
