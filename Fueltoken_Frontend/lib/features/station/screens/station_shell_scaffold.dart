import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

/// Coquille station avec une barre basse inspirée de `botontabs.jfif`.
class StationShellScaffold extends StatelessWidget {
  const StationShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goTo(BuildContext context, String path) {
    HapticFeedback.selectionClick();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F4),
      extendBody: false,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: SizedBox(
            height: 126,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFD6DADF),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StationBarTab(
                              label: 'Accueil',
                              icon: Icons.home_rounded,
                              selected: selected == 0,
                              onTap: () => _goTo(context, '/station/home'),
                            ),
                          ),
                          const SizedBox(width: 112),
                          Expanded(
                            child: _StationBarTab(
                              label: 'Profil',
                              icon: Icons.person_outline_rounded,
                              selected: selected == 2,
                              onTap: () => _goTo(context, '/station/profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -6,
                  child: Semantics(
                    button: true,
                    selected: selected == 1,
                    label: 'Scan',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _goTo(context, '/station/scan'),
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          width: 112,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: AppColors.leaderGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFE7E7E2),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.leaderGreen.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Scan',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.leaderGreen,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _StationBarTab extends StatelessWidget {
  const _StationBarTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.onSurfaceVariant;
    final active = AppColors.leaderGreen;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: selected ? active : inactive),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? active : inactive,
                    height: 1.0,
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
