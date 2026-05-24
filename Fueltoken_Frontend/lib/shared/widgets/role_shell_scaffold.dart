import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Destination d’onglet pour [RoleShellScaffold].
class RoleShellDestination {
  const RoleShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Coquille avec barre d’onglets statique sans animation.
class RoleShellScaffold extends StatelessWidget {
  const RoleShellScaffold({
    super.key,
    required this.navigationShell,
    required this.destinations,
    required this.accentColor,
    this.scaffoldBackgroundColor,
  }) : assert(destinations.length > 0);

  final StatefulNavigationShell navigationShell;
  final List<RoleShellDestination> destinations;
  final Color accentColor;

  final Color? scaffoldBackgroundColor;

  void _onTabTap(int index) {
    if (index == navigationShell.currentIndex) {
      navigationShell.goBranch(index, initialLocation: true);
      return;
    }
    HapticFeedback.selectionClick();
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final selected = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final pageBg = scaffoldBackgroundColor ?? theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: pageBg,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Container(
        width: double.infinity,
        height: 86,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++) ...[
              Expanded(
                child: _RoleTabButton(
                  destination: destinations[i],
                  selected: i == selected,
                  accentColor: accentColor,
                  onTap: () => _onTabTap(i),
                ),
              ),
              if (i != destinations.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleTabButton extends StatelessWidget {
  const _RoleTabButton({
    required this.destination,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final RoleShellDestination destination;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final activeColor = accentColor;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.transparent,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 26,
                  color: selected ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.0,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? activeColor : inactiveColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
