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
      label: l10n.navWallet,
      icon: Icons.sync_alt_outlined,
      selectedIcon: Icons.sync_alt_rounded,
    ),
    _ClientTabDestination(
      label: l10n.navHistory,
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _ClientTabDestination(
      label: l10n.navPortfolio,
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
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
      case 1: // Opérations
        WalletRefreshBus.instance.bump();
        break;
      case 2: // Historique
        ClientHistoryRefreshBus.instance.bump();
        break;
      case 3: // Portefeuille : carnets + QR
        FacesRefreshBus.instance.bump();
        QrRefreshBus.instance.bump();
        break;
    }
  }

  void _onPortfolioDestinationSelected(
    BuildContext context,
    _PortfolioDestination destination,
  ) {
    HapticFeedback.selectionClick();
    switch (destination) {
      case _PortfolioDestination.carnets:
        FacesRefreshBus.instance.bump();
        context.go('/portfolio/faces');
        break;
      case _PortfolioDestination.qr:
        QrRefreshBus.instance.bump();
        context.go('/portfolio/qr');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Keep the iPhone safe area inside the navigation surface so the bar's
    // background reaches the physical bottom edge without leaving a gap.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isTabletLayout = viewportWidth >= 700;
    final destinations = _destinations(AppLocalizations.of(context));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SizedBox(
        height: (isTabletLayout ? 124 : 86) + bottomInset,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isTabletLayout ? 640 : double.infinity,
            ),
            child: Container(
              width: double.infinity,
              height: (isTabletLayout ? 124 : 86) + bottomInset,
              padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset),
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
                border: Border.all(
                  color: AppColors.line.withValues(alpha: 0.8),
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++) ...[
                    Expanded(
                      child: i == 3
                          ? _PortfolioPopupTabButton(
                              destination: destinations[i],
                              selected: i == navigationShell.currentIndex,
                              onSelected: (destination) =>
                                  _onPortfolioDestinationSelected(
                                    context,
                                    destination,
                                  ),
                            )
                          : _ClientTabButton(
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
          ),
        ),
      ),
    );
  }
}

enum _PortfolioDestination { carnets, qr }

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
            child: _ClientTabContent(
              destination: destination,
              selected: selected,
            ),
          ),
        ),
      ),
    );
  }
}

class _PortfolioPopupTabButton extends StatelessWidget {
  const _PortfolioPopupTabButton({
    required this.destination,
    required this.selected,
    required this.onSelected,
  });

  final _ClientTabDestination destination;
  final bool selected;
  final ValueChanged<_PortfolioDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PopupMenuButton<_PortfolioDestination>(
      tooltip: destination.label,
      onSelected: onSelected,
      color: AppColors.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => [
        PopupMenuItem<_PortfolioDestination>(
          value: _PortfolioDestination.carnets,
          child: _PortfolioPopupEntry(
            icon: Icons.confirmation_number_outlined,
            label: l10n.carnetsTitle,
          ),
        ),
        PopupMenuItem<_PortfolioDestination>(
          value: _PortfolioDestination.qr,
          child: _PortfolioPopupEntry(
            icon: Icons.qr_code_2_outlined,
            label: l10n.qrsTitle,
          ),
        ),
      ],
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _ClientTabContent(
            destination: destination,
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _PortfolioPopupEntry extends StatelessWidget {
  const _PortfolioPopupEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.leaderGreen, size: 22),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ClientTabContent extends StatelessWidget {
  const _ClientTabContent({required this.destination, required this.selected});

  final _ClientTabDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.leaderGreen;
    final inactiveColor = AppColors.muted;
    final isTabletLayout = MediaQuery.sizeOf(context).width >= 700;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: isTabletLayout ? 42 : 26,
          color: selected ? activeColor : inactiveColor,
        ),
        SizedBox(height: isTabletLayout ? 8 : 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            destination.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: isTabletLayout ? 16.5 : 10.5,
              height: 1.0,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? activeColor : inactiveColor,
            ),
          ),
        ),
      ],
    );
  }
}
