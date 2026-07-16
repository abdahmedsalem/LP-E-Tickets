import 'package:flutter/material.dart';

class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({
    super.key,
    required this.fromLabel,
    required this.toLabel,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onApply,
    this.fromPrefix = 'Du',
    this.toPrefix = 'Au',
    this.applySemanticLabel,
    this.applyColor = const Color(0xFF1B8F3A),
  });

  final String fromLabel;
  final String toLabel;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onApply;
  final String fromPrefix;
  final String toPrefix;
  final String? applySemanticLabel;
  final Color applyColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          flex: 43,
          child: _DateRangeChip(
            label: fromPrefix,
            value: fromLabel,
            onTap: onPickFrom,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          flex: 43,
          child: _DateRangeChip(
            label: toPrefix,
            value: toLabel,
            onTap: onPickTo,
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: applyColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onApply,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Semantics(
                label: applySemanticLabel,
                button: true,
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF374151), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Color(0xFF374151),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
