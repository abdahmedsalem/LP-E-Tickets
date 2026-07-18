import 'package:flutter/material.dart';

/// Displays a complete card title on one line without truncation.
class SingleLineCardTitle extends StatelessWidget {
  const SingleLineCardTitle({
    super.key,
    required this.text,
    required this.style,
    this.alignment = AlignmentDirectional.centerStart,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
