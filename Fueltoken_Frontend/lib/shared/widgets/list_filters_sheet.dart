import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'filter_chip.dart';

/// Section de filtres pour une bottom sheet (valeurs, types, expiration, etc.).
class ListFilterSection {
  const ListFilterSection({
    required this.title,
    required this.options,
  });

  final String title;
  final List<ListFilterOption> options;
}

class ListFilterOption {
  const ListFilterOption({
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
}

/// Ouvre une feuille de filtres structurée (évolutive quand les options augmentent).
Future<void> showListFiltersSheet({
  required BuildContext context,
  required List<ListFilterSection> sections,
  VoidCallback? onClearAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filtres',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (onClearAll != null)
                        TextButton(
                          onPressed: () {
                            onClearAll();
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Tout effacer',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Fermer',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
                    children: [
                      for (final section in sections) ...[
                        Text(
                          section.title.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.75,
                            color: AppColors.muted.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final opt in section.options)
                              AppFilterChip(
                                label: opt.label,
                                active: opt.selected,
                                onTap: () {
                                  opt.onSelect();
                                  Navigator.pop(ctx);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Voir les résultats',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
