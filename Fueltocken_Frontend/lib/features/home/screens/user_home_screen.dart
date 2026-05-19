import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../data/models/face_line.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/fuel_brand_lottie.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../wallet/bloc/wallet_cubit.dart';

class UserHomeScreen extends StatelessWidget {
  const UserHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    return BlocProvider(
      create: (_) => WalletCubit(ownerId: user.id),
      child: const _UserHomeBody(),
    );
  }
}

class _UserHomeBody extends StatelessWidget {
  const _UserHomeBody();

  int _totalTickets(List<FaceLine> lines) {
    var n = 0;
    for (final l in lines) {
      if (l.isExpired || l.availableQty <= 0) continue;
      n += l.availableQty;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        if (user == null) {
          return const Scaffold(body: AppPageLoading());
        }
        final initials = _initialsOf(user.name);

        return Scaffold(
          backgroundColor: context.fuelPageBackground,
          body: SafeArea(
            bottom: false,
            child: BlocBuilder<WalletCubit, WalletState>(
              builder: (ctx, wallet) {
                return RefreshIndicator(
                  color: AppColors.leaderGreen,
                  onRefresh: () async => ctx.read<WalletCubit>().refresh(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.leaderGreen.withValues(
                                      alpha: 0.22,
                                    ),
                                    AppColors.accentTeal.withValues(
                                      alpha: 0.18,
                                    ),
                                  ],
                                ),
                                border: Border.all(
                                  color: AppColors.leaderGreen.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: AppColors.leaderGreenDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bonjour,',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.35,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.verified_rounded,
                                        size: 15,
                                        color: AppColors.leaderGreen,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Compte vérifié',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _HomeTopAction(
                              icon: Icons.notifications_outlined,
                              onTap: () => ctx.push('/notifications'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (wallet.loadError != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Material(
                            color: AppColors.brandRedSoft,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                wallet.loadError!,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.brandRed,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClientHomeWalletCard(
                          amount: wallet.amount,
                          totalTickets: _totalTickets(wallet.faceLines),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Actions rapides',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 0.78,
                                child: _QuickActionCard(
                                  title: 'Acheter',
                                  icon: Icons.add_shopping_cart_outlined,
                                  onTap: () => context.push('/purchases/new'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 0.78,
                                child: _QuickActionCard(
                                  title: 'Émettre QR',
                                  icon: Icons.qr_code_scanner_rounded,
                                  onTap: () => context.push('/qr/emit'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 0.78,
                                child: _QuickActionCard(
                                  title: 'Splitter',
                                  icon: Icons.account_tree_outlined,
                                  onTap: () => context.push('/qr'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.map((p) => p.isEmpty ? '' : p[0]).take(2).join().toUpperCase();
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final circleDiameter = math.min(54.0, math.max(46.0, cardWidth * 0.42));
        final iconSize = circleDiameter * 0.42;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.line.withValues(alpha: 0.9),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.055),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: math.max(10.0, cardWidth * 0.07),
                  vertical: math.max(12.0, cardWidth * 0.085),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: circleDiameter,
                      height: circleDiameter,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        color: AppColors.leaderGreen,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: math.max(10.0, cardWidth * 0.08)),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: math.min(
                          14.5,
                          math.max(12.5, cardWidth * 0.13),
                        ),
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeTopAction extends StatelessWidget {
  const _HomeTopAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.85),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
