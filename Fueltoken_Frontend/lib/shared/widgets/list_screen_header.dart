import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class ListScreenFilterOption<T> {
  const ListScreenFilterOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;
  final int? count;
}

/// Shared title and horizontal filters used by client list screens.
class ListScreenHeader<T> extends StatelessWidget {
  const ListScreenHeader({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.horizontalPadding = 26,
    this.topPadding = 16,
    this.titleFilterGap = 18,
  });

  final String title;
  final List<ListScreenFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final double horizontalPadding;
  final double topPadding;
  final double titleFilterGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            0,
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
        ),
        SizedBox(height: titleFilterGap),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                _ListScreenFilterChip(
                  label: options[i].label,
                  selected: selected == options[i].value,
                  count: options[i].count,
                  onTap: () => onSelected(options[i].value),
                ),
                if (i != options.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ListScreenFilterChip extends StatelessWidget {
  const _ListScreenFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            count == null ? label : '$label $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
