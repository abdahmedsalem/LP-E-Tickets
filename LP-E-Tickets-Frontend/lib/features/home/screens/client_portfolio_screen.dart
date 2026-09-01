import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/screen_header.dart';

/// Point d'entrée unique vers les carnets et les QR du client.
class ClientPortfolioScreen extends StatelessWidget {
  const ClientPortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(title: l10n.navPortfolio, showBack: false),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
                children: [
                  _PortfolioEntryCard(
                    title: l10n.carnetsTitle,
                    icon: Icons.confirmation_number_outlined,
                    color: AppColors.leaderGreen,
                    onTap: () => context.go('/portfolio/faces'),
                  ),
                  const SizedBox(height: 14),
                  _PortfolioEntryCard(
                    title: l10n.qrsTitle,
                    icon: Icons.qr_code_2_outlined,
                    color: AppColors.primaryDeep,
                    onTap: () => context.go('/portfolio/qr'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioEntryCard extends StatelessWidget {
  const _PortfolioEntryCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.muted,
            size: 24,
          ),
        ],
      ),
    );
  }
}
