import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../l10n/app_localizations.dart';

/// Coquille client — barre tabs personnalisée.
class ClientShellScaffold extends StatelessWidget {
  const ClientShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  List<_ClientTabDestination> _destinations(AppLocalizations l10n) => [
    _ClientTabDestination(
      label: l10n.navHome,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _ClientTabDestination(
      label: l10n.navCarnets,
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number,
    ),
    _ClientTabDestination(
      label: l10n.navQr,
      icon: Icons.qr_code_2_outlined,
      selectedIcon: Icons.qr_code_2,
    ),
    _ClientTabDestination(
      label: l10n.navWallet,
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
    ),
    _ClientTabDestination(
      label: l10n.navHistory,
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
  ];

  void _onTabTap(int index) {
    final isSameTab = index == navigationShell.currentIndex;
    if (isSameTab) {
      navigationShell.goBranch(index, initialLocation: true);
    } else {
      HapticFeedback.selectionClick();
      navigationShell.goBranch(index);
    }
    // Bumper les buses selon l'onglet activé pour forcer le rechargement
    switch (index) {
      case 0: // Accueil / Wallet
        WalletRefreshBus.instance.bump();
        break;
      case 1: // Carnets / Faces
        FacesRefreshBus.instance.bump();
        break;
      case 2: // QR
        QrRefreshBus.instance.bump();
        break;
      case 3: // Portefeuille
        WalletRefreshBus.instance.bump();
        break;
      case 4: // Historique
        ClientHistoryRefreshBus.instance.bump();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final destinations = _destinations(AppLocalizations.of(context));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Container(
        width: double.infinity,
        height: 86 + bottomInset,
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        decoration: BoxDecoration(
          color: AppColors.surface,
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
          border: Border.all(color: AppColors.line.withValues(alpha: 0.8)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++) ...[
              Expanded(
                child: _ClientTabButton(
                  destination: destinations[i],
                  selected: i == navigationShell.currentIndex,
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

class _ClientTabDestination {
  const _ClientTabDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _ClientTabButton extends StatelessWidget {
  const _ClientTabButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ClientTabDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.leaderGreen;
    final inactiveColor = AppColors.muted;

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
