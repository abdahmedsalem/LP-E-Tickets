import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class OverviewInfoItem {
  const OverviewInfoItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class OverviewInfoCard extends StatelessWidget {
  const OverviewInfoCard({
    super.key,
    required this.items,
  });

  final List<OverviewInfoItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _OverviewInfoRow(
              label: items[i].label,
              value: items[i].value,
            ),
            if (i < items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.line),
          ],
        ],
      ),
    );
  }
}

class _OverviewInfoRow extends StatelessWidget {
  const _OverviewInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 7,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
