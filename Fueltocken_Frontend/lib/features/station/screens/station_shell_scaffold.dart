import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/role_shell_scaffold.dart';

/// Coquille station — accents bleus / jaunes existants, même barre animée que le client.
class StationShellScaffold extends StatelessWidget {
  const StationShellScaffold({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static const _destinations = <RoleShellDestination>[
    RoleShellDestination(
      label: 'Accueil',
      icon: Icons.local_gas_station_outlined,
      selectedIcon: Icons.local_gas_station_rounded,
    ),
    RoleShellDestination(
      label: 'Scanner',
      icon: Icons.qr_code_scanner_outlined,
      selectedIcon: Icons.qr_code_scanner_rounded,
    ),
    RoleShellDestination(
      label: 'Journal',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    RoleShellDestination(
      label: 'Profil',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return RoleShellScaffold(
      navigationShell: navigationShell,
      destinations: _destinations,
      accentColor: AppColors.leaderGreen,
    );
  }
}
