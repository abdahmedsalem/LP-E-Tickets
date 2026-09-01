import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/fuel_brand_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../wallet/bloc/wallet_cubit.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  WalletCubit? _walletCubit;
  String? _walletOwnerId;
  String? _walletCompanyId;

  void _syncWalletCubit() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      _walletCubit?.close();
      _walletCubit = null;
      _walletOwnerId = null;
      _walletCompanyId = null;
      return;
    }
    final companyId = AppEnvironment.companyIdForUser(user);
    if (_walletCubit != null &&
        _walletOwnerId == user.id &&
        _walletCompanyId == companyId) {
      return;
    }
    _walletCubit?.close();
    _walletCubit = WalletCubit(ownerId: user.id, companyId: companyId);
    _walletOwnerId = user.id;
    _walletCompanyId = companyId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWalletCubit();
  }

  @override
  void dispose() {
    _walletCubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: _HomeLoadingSkeleton());
    }
    _syncWalletCubit();
    return BlocProvider.value(
      value: _walletCubit!,
      child: const _UserHomeBody(),
    );
  }
}

class _UserHomeBody extends StatefulWidget {
  const _UserHomeBody();

  @override
  State<_UserHomeBody> createState() => _UserHomeBodyState();
}

class _UserHomeBodyState extends State<_UserHomeBody> {
  Timer? _pollTimer;
  late final VoidCallback _walletBusListener;
  String _walletCurrency = Formatters.fallbackCurrency;
  String? _walletCurrencyCompanyId;

  Future<void> _loadWalletCurrency() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    final companyId = AppEnvironment.companyIdForUser(user);
    if (_walletCurrencyCompanyId == companyId) return;
    _walletCurrencyCompanyId = companyId;

    try {
      final types = await AcpecCarnetCatalogService.instance
          .listPurchaseOfferTypes(companyId: companyId);
      final currencies = types
          .map((type) => type.displayCurrency.trim())
          .where((currency) => currency.isNotEmpty)
          .toSet();

      if (!mounted || currencies.isEmpty) return;

      final resolvedCurrency = currencies.length == 1
          ? currencies.single
          : Formatters.fallbackCurrency;

      setState(() {
        _walletCurrency = resolvedCurrency;
      });
      Formatters.setDefaultCurrency(resolvedCurrency);
    } catch (_) {
      // La devise reste le fallback central si le catalogue est indisponible.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWalletCurrency();
    _walletBusListener = () {
      if (!mounted || context.read<WalletCubit>().isClosed) return;
      context.read<WalletCubit>().refresh();
    };
    WalletRefreshBus.instance.revision.addListener(_walletBusListener);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || context.read<WalletCubit>().isClosed) return;
      context.read<WalletCubit>().refresh();
    });
  }

  @override
  void dispose() {
    WalletRefreshBus.instance.revision.removeListener(_walletBusListener);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        if (user == null) {
          return const Scaffold(body: _HomeLoadingSkeleton());
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            bottom: false,
            child: BlocBuilder<WalletCubit, WalletState>(
              builder: (ctx, wallet) {
                final viewportWidth = MediaQuery.sizeOf(ctx).width;
                final horizontalPadding = viewportWidth < 340 ? 12.0 : 16.0;
                final actionGap = viewportWidth < 340 ? 10.0 : 12.0;
                final walletHeight = viewportWidth < 340 ? 112.0 : 106.0;

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
                        padding: EdgeInsetsDirectional.fromSTEB(
                          horizontalPadding,
                          4,
                          horizontalPadding,
                          0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => ctx.go('/settings'),
                              customBorder: const CircleBorder(),
                              child: Container(
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
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.leaderGreenDark,
                                  size: 27,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 6),
                              child: SizedBox(width: 6),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
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
                                      Flexible(
                                        child: Text(
                                          l10n.homeVerifiedAccount,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: SizedBox(
                          height: walletHeight,
                          child: ClientHomeWalletCard(
                            amount: wallet.amount,
                            currency: _walletCurrency,
                            loading: wallet.loading,
                          ),
                        ),
                      ),
                      if (wallet.loadError != null &&
                          wallet.loadError!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: _BackendUnavailableBanner(
                            message:
                                Localizations.localeOf(ctx).languageCode == 'ar'
                                ? l10n.commonServerUnavailable
                                : wallet.loadError!,
                            onRetry: () => ctx.read<WalletCubit>().refresh(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Text(
                          l10n.homeQuickActions,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.18,
                                    child: _QuickActionCard(
                                      title: l10n.homeBuyCarnets,
                                      icon: Icons.add_shopping_cart_outlined,
                                      onTap: () =>
                                          context.push('/purchases/new'),
                                    ),
                                  ),
                                ),
                                SizedBox(width: actionGap),
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.18,
                                    child: _QuickActionCard(
                                      title: l10n.homeGenerateQr,
                                      icon: Icons.qr_code_scanner_rounded,
                                      onTap: () => context.push('/qr/emit'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: actionGap),
                            Row(
                              children: [
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.18,
                                    child: _QuickActionCard(
                                      title: l10n.homeTransferCarnets,
                                      icon: Icons.account_tree_outlined,
                                      onTap: () =>
                                          context.push('/transfer-carnets'),
                                    ),
                                  ),
                                ),
                                SizedBox(width: actionGap),
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.18,
                                    child: _QuickActionCard(
                                      title: l10n.homeTransferTickets,
                                      icon: Icons.confirmation_number_outlined,
                                      onTap: () =>
                                          context.push('/transfer-tickets'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: actionGap),
                            Row(
                              children: [
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 2.45,
                                    child: _QuickActionCard(
                                      title: 'Carte des stations',
                                      icon: Icons.map_outlined,
                                      onTap: () =>
                                          context.push('/stations-map'),
                                    ),
                                  ),
                                ),
                              ],
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
}

class _BackendUnavailableBanner extends StatelessWidget {
  const _BackendUnavailableBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.error.withValues(alpha: 0.28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final retryButton = TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.leaderGreenDark,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(AppLocalizations.of(context).commonRetry),
            );
            final messageRow = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_rounded, color: scheme.error, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 330) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  messageRow,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: retryButton,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: messageRow),
                const SizedBox(width: 8),
                retryButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          AppLoadingSkeleton(
            style: AppLoadingSkeletonStyle.historyRows,
            itemCount: 2,
          ),
          SizedBox(height: 20),
          AppLoadingSkeleton(
            style: AppLoadingSkeletonStyle.qrGeneration,
            itemCount: 2,
          ),
        ],
      ),
    );
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
        final cardHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : cardWidth / 1.18;
        final compact = cardHeight < 112 || cardWidth < 130;
        final circleDiameter = compact
            ? math.min(46.0, math.max(38.0, cardWidth * 0.36))
            : math.min(52.0, math.max(46.0, cardWidth * 0.38));
        final iconSize = circleDiameter * 0.44;
        final horizontalPadding = compact
            ? math.max(8.0, cardWidth * 0.06)
            : math.max(10.0, cardWidth * 0.08);
        final verticalPadding = compact
            ? math.max(8.0, cardHeight * 0.065)
            : math.max(10.0, cardWidth * 0.07);
        final titleGap = compact
            ? math.max(6.0, cardHeight * 0.055)
            : math.max(8.0, cardWidth * 0.055);
        final titleFontSize = compact
            ? math.min(11.4, math.max(10.0, cardWidth * 0.095))
            : math.min(12.0, math.max(10.8, cardWidth * 0.102));

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: circleDiameter,
                      height: circleDiameter,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5F5F5),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        color: AppColors.leaderGreen,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: titleGap),
                    SingleLineCardTitle(
                      text: title,
                      alignment: Alignment.center,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w700,
                        height: 1.14,
                        color: const Color(0xFF111111),
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
