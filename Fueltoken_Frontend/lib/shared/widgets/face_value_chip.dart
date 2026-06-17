import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// Small green chip that displays a face value (e.g. 500, 1000).
class FaceValueChip extends StatelessWidget {
  const FaceValueChip({
    super.key,
    required this.value,
    this.size = 50,
    this.gradient = true,
    this.currency,
  });

  final num value;
  final double size;
  final bool gradient;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final valueFontSize = (size * 0.28).clamp(11.0, 19.0);
    final currencyFontSize = (size * 0.16).clamp(7.5, 11.0);
    final unit = Formatters.currencyOrDefault(currency);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF34D399), Color(0xFF16A34A)],
              )
            : null,
        color: gradient ? null : const Color(0xFFE8F5EC),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: gradient
            ? const [
                BoxShadow(
                  color: Color(0x334ADE80),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.08,
        vertical: size * 0.08,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: valueFontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: size * 0.04),
            Text(
              unit,
              style: TextStyle(
                fontSize: currencyFontSize,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
