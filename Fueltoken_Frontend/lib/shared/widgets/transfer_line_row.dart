import 'package:flutter/material.dart';

import 'confirmation_line_main_row.dart';

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
    return ConfirmationLineMainRow(
      title: title,
      amount: amount,
      quantity: quantity,
      showQuantity: showQuantity,
    );
  }
}
