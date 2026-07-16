import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'amount_inline.dart';
import 'quantity_circle_badge.dart';

class TransferLineRow extends StatelessWidget {
  const TransferLineRow({
    super.key,
    required this.title,
    required this.amount,
    this.quantity,
    this.showQuantity = true,
  });

  final String title;
  final int amount;
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
            height: 20,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showQuantity) ...[
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Center(
              child: QuantityCircleBadge(quantity: quantity ?? 0, size: 18),
            ),
          ),
          const SizedBox(width: 10),
        ] else
          const SizedBox(width: 10),
        Expanded(
          flex: showQuantity ? 4 : 6,
          child: AmountInline(
            amount: amount,
            textAlign: TextAlign.end,
            valueStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
            ),
          ),
        ),
      ],
    );
  }
}
