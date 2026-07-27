import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

/// Coquille admin avec barre de navigation à 3 onglets.
class AdminShellScaffold extends StatelessWidget {
  const AdminShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    if (index == navigationShell.currentIndex) {
      navigationShell.goBranch(index, initialLocation: true);
      return;
    }
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AdminBottomTabsBar(
        selectedIndex: navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

class AdminBottomTabsBar extends StatelessWidget {
  const AdminBottomTabsBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static const _items = <_AdminTabItem>[
    _AdminTabItem(
      label: 'Accueil',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _AdminTabItem(
      label: 'Achats',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
    ),
    _AdminTabItem(
      label: 'Profil',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          height: 82,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.zero,
            border: Border(
              top: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _AdminTabButton(
                  item: _items[0],
                  selected: selectedIndex == 0,
                  onTap: () => onTap(0),
                  accent: AppColors.success,
                ),
              ),
              Expanded(
                child: _AdminTabButton(
                  item: _items[1],
                  selected: selectedIndex == 1,
                  onTap: () => onTap(1),
                  accent: AppColors.success,
                ),
              ),
              Expanded(
                child: _AdminTabButton(
                  item: _items[2],
                  selected: selectedIndex == 2,
                  onTap: () => onTap(2),
                  accent: AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTabItem {
  const _AdminTabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _AdminTabButton extends StatelessWidget {
  const _AdminTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final _AdminTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : Colors.grey.shade500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              color: color,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
