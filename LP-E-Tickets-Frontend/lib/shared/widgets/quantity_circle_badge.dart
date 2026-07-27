import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

class QuantityCircleBadge extends StatelessWidget {
  const QuantityCircleBadge({
    super.key,
    required this.quantity,
    this.size = 18,
    this.backgroundColor = const Color(0xFF2E7D32),
    this.textStyle = const TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1,
    ),
  });

  final int quantity;
  final double size;
  final Color backgroundColor;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        Formatters.numberFr(quantity),
        textAlign: TextAlign.center,
        style: textStyle,
      ),
    );
  }
}
