import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/models/user_role.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _HistoryQuickFilter { all, purchases, transfer, consumption, qr }

class _TransactionsScreenState extends State<TransactionsScreen> {
  TxType? _filter;
  _HistoryQuickFilter _quickFilter = _HistoryQuickFilter.all;

  /// Types retirés de l'UI (ex. portefeuille) se comportent comme tous les filtres.
  TxType? get _effectiveFilter =>
      _filter == TxType.walletLedger ? null : _filter;

  static const int _pageSize = 20;

  /// Limite de sécurité pour charger tout l'historique sur une période (filtre type).
  static const int _maxPagesFullRange = 80;

  final ScrollController _scroll = ScrollController();

  List<BusinessTransaction> _acpecItems = [];
  bool _acpecLoading = true;
  bool _acpecLoadingMore = false;
  String? _acpecError;
  bool _acpecHasMore = true;
  int? _acpecTotal;
  VoidCallback? _historyRevisionListener;
  int _lastHistoryRevision = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onAcpecScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppEnvironment.useAcpecLiveData) {
        _loadAcpec(reset: true);
      } else {
        setState(() => _acpecLoading = false);
      }
    });
    _historyRevisionListener = () {
      if (!mounted || !AppEnvironment.useAcpecLiveData) return;
      final rev = ClientHistoryRefreshBus.instance.revision.value;
      if (rev == _lastHistoryRevision) return;
      _lastHistoryRevision = rev;
      unawaited(_reloadAcpecForCurrentFilter());
    };
    ClientHistoryRefreshBus.instance.revision.addListener(
      _historyRevisionListener!,
    );
  }

  @override
  void dispose() {
    ClientHistoryRefreshBus.instance.revision.removeListener(
      _historyRevisionListener ?? () {},
    );
    _scroll.removeListener(_onAcpecScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Route 5.6 : limit, offset (pas de filtre date côté API).
  Map<String, dynamic> _clientTxParams({
    required int limit,
    required int offset,
  }) {
    return {'limit': limit, 'offset': offset};
  }

  Map<String, dynamic> _stationTxParams({
    required int limit,
    required int offset,
  }) => {'limit': limit, 'offset': offset};

  bool _matchesTypeFilter(BusinessTransaction t) {
    final f = _effectiveFilter;
    if (f == null) return true;
    return AcpecTransactionsMapper.matchesClientFilter(t, f);
  }

  bool _matchesQuickFilter(BusinessTransaction t) {
    switch (_quickFilter) {
      case _HistoryQuickFilter.all:
        return true;
      case _HistoryQuickFilter.purchases:
        return t.type == TxType.purchaseValidated ||
            t.type == TxType.purchaseSubmitted ||
            t.type == TxType.purchaseRejected;
      case _HistoryQuickFilter.transfer:
        return t.type == TxType.carnetTransfer ||
            t.type == TxType.carnetReceived;
      case _HistoryQuickFilter.consumption:
        return t.type == TxType.stationConsumption;
      case _HistoryQuickFilter.qr:
        return t.type == TxType.qrEmission ||
            t.type == TxType.qrSeparer ||
            t.type == TxType.qrRetirer ||
            t.type == TxType.qrBlocked ||
            t.type == TxType.expiration;
    }
  }

  void _setQuickFilter(_HistoryQuickFilter next) {
    if (_quickFilter == next) return;
    setState(() => _quickFilter = next);
    if (AppEnvironment.useAcpecLiveData) {
      unawaited(_reloadAcpecForCurrentFilter());
    }
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _refreshCurrentHistory() async {
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {});
      return;
    }
    await _reloadAcpecForCurrentFilter();
  }

  void _onAcpecScroll() {
    if (!AppEnvironment.useAcpecLiveData || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    if (_scroll.position.pixels >= max - 280) {
      _loadAcpec(reset: false);
    }
  }

  List<BusinessTransaction> _mergeHistory(
    List<BusinessTransaction> primary,
    List<BusinessTransaction> extra,
  ) {
    final out = <BusinessTransaction>[];
    final seen = <String>{};
    void addTx(BusinessTransaction tx) {
      final key = '${tx.type.name}:${tx.lotId ?? tx.id}';
      if (seen.add(key)) out.add(tx);
    }

    for (final tx in primary) {
      addTx(tx);
    }
    for (final tx in extra) {
      addTx(tx);
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<List<BusinessTransaction>> _submittedPurchasesHistory(
    dynamic user,
  ) async {
    if (user == null || user.role != UserRole.user) return const [];
    try {
      final raw = await OdooFueltokenFacade().purchasesList(
        const <String, dynamic>{},
      );
      final lots = AcpecPurchasesMapper.fromRpcResult(
        raw,
        clientId: user.id,
        clientName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      return AcpecTransactionsMapper.fromSubmittedPurchases(
        lots,
        userId: user.id,
        userName: user.name,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadAcpec({required bool reset}) async {
    if (!AppEnvironment.useAcpecLiveData) return;
    if (!reset && (_acpecLoadingMore || !_acpecHasMore || _acpecLoading)) {
      return;
    }

    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _acpecLoading = false;
        _acpecError = 'Session requise.';
      });
      return;
    }

    if (reset) {
      setState(() {
        _acpecLoading = true;
        _acpecError = null;
        _acpecHasMore = true;
        _acpecTotal = null;
      });
    } else {
      setState(() => _acpecLoadingMore = true);
    }

    final offset = reset ? 0 : _acpecItems.length;

    try {
      final dynamic raw;
      if (user.role == UserRole.station) {
        raw = await OdooFueltokenFacade().stationTransactions(
          _stationTxParams(limit: _pageSize, offset: offset),
        );
      } else {
        raw = await OdooFueltokenFacade().transactions(
          _clientTxParams(limit: _pageSize, offset: offset),
        );
      }
      final page = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: _pageSize,
        requestedOffset: offset,
      );
      if (!mounted) return;
      final batch = page.items.where(_matchesTypeFilter).toList();
      final submitted = reset
          ? await _submittedPurchasesHistory(user)
          : const <BusinessTransaction>[];
      setState(() {
        if (reset) {
          _acpecItems = _mergeHistory(batch, submitted);
          _lastHistoryRevision =
              ClientHistoryRefreshBus.instance.revision.value;
        } else {
          _acpecItems.addAll(batch);
        }
        _acpecTotal = page.totalCount ?? _acpecTotal;
        _acpecHasMore = page.hasMore;
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : ErrorPresenter.message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = ErrorPresenter.isBackendUnavailable(e)
            ? ErrorPresenter.backendUnavailable()
            : ErrorPresenter.message(e);
      });
    }
  }

  /// Charge toutes les pages de la période (nécessaire pour un filtre type correct côté client).
  Future<void> _loadAcpecFullRange() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _acpecLoading = false;
        _acpecError = 'Session requise.';
      });
      return;
    }

    setState(() {
      _acpecLoading = true;
      _acpecLoadingMore = false;
      _acpecError = null;
      _acpecItems = [];
      _acpecHasMore = false;
      _acpecTotal = null;
    });

    final all = <BusinessTransaction>[];
    var offset = 0;
    int? totalHint;

    try {
      while (true) {
        final dynamic raw;
        if (user.role == UserRole.station) {
          raw = await OdooFueltokenFacade().stationTransactions(
            _stationTxParams(limit: _pageSize, offset: offset),
          );
        } else {
          raw = await OdooFueltokenFacade().transactions(
            _clientTxParams(limit: _pageSize, offset: offset),
          );
        }
        final page = AcpecTransactionsMapper.parsePage(
          raw,
          userId: user.id,
          userName: user.name,
          requestedLimit: _pageSize,
          requestedOffset: offset,
        );
        totalHint = page.totalCount ?? totalHint;
        all.addAll(page.items.where(_matchesTypeFilter));
        offset += page.items.length;
        if (!page.hasMore || page.items.isEmpty) break;
        if (offset >= _pageSize * _maxPagesFullRange) break;
      }
      final submitted = await _submittedPurchasesHistory(user);
      if (!mounted) return;
      setState(() {
        _acpecItems = _mergeHistory(all, submitted);
        _lastHistoryRevision = ClientHistoryRefreshBus.instance.revision.value;
        _acpecTotal = totalHint ?? all.length;
        _acpecHasMore = false;
        _acpecLoading = false;
        _acpecError = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecError = ErrorPresenter.isBackendUnavailable(e)
            ? ErrorPresenter.backendUnavailable()
            : ErrorPresenter.message(e);
      });
    }
  }

  Future<void> _reloadAcpecForCurrentFilter() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    if (_effectiveFilter == null && _quickFilter == _HistoryQuickFilter.all) {
      await _loadAcpec(reset: true);
    } else {
      await _loadAcpecFullRange();
    }
  }

  static String _titleForRole(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Historique';
      case UserRole.station:
        return 'Historique station';
      case UserRole.admin:
        return 'Historique global';
    }
  }

  static String _emptyTitle(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Aucun mouvement pour l\u0027instant';
      case UserRole.station:
        return 'Aucune activité enregistrée';
      case UserRole.admin:
        return 'Historique vide';
    }
  }

  static String _emptyMessage(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Vos achats, QR préparés, envois et utilisations apparaîtront ici.';
      case UserRole.station:
        return 'Les contrôles et utilisations traités pour cette station s\u0027afficheront ici.';
      case UserRole.admin:
        return 'Synchronisez ou ajoutez des données : l\u0027historique global se remplira automatiquement.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        if (user == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: ListView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(26, 18, 26, 96),
                children: [
                  AppLoadingSkeleton(
                    style: AppLoadingSkeletonStyle.historyRows,
                    itemCount: 5,
                  ),
                ],
              ),
            ),
          );
        }

        final acpec = AppEnvironment.useAcpecLiveData;
        final showBack = user.role != UserRole.user;

        if (!acpec) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    onBack: () => popOrGoRoleHome(context, user.role),
                    showBack: showBack,
                    leadingOnlyWhenNavigatorCanPop: true,
                  ),
                  const Expanded(child: ApiRequiredView()),
                ],
              ),
            ),
          );
        }

        final List<BusinessTransaction> base = _acpecItems;

        final scoped = base;
        final visible = scoped.where(_matchesQuickFilter).toList();
        final txs = _effectiveFilter == null
            ? visible
            : visible
                  .where(
                    (t) => AcpecTransactionsMapper.matchesClientFilter(
                      t,
                      _effectiveFilter!,
                    ),
                  )
                  .toList();

        final groups = _groupByDay(txs);

        if (acpec &&
            _acpecLoading &&
            _acpecItems.isEmpty &&
            _acpecError == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    onBack: () => popOrGoRoleHome(context, user.role),
                    showBack: showBack,
                    leadingOnlyWhenNavigatorCanPop: true,
                  ),
                  Expanded(
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
                      children: [
                        AppLoadingSkeleton(
                          style: AppLoadingSkeletonStyle.historyRows,
                          itemCount: 5,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (acpec && _acpecError != null && _acpecItems.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    onBack: () => popOrGoRoleHome(context, user.role),
                    showBack: showBack,
                    leadingOnlyWhenNavigatorCanPop: true,
                  ),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(child: AppErrorLottie(size: 120)),
                        const SizedBox(height: 16),
                        Text(
                          _acpecError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: FilledButton.tonalIcon(
                            onPressed: () =>
                                unawaited(_reloadAcpecForCurrentFilter()),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('R\u00e9essayer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _titleForRole(user.role),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: -0.2,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: _HistoryFilterChips(
                    selected: _quickFilter,
                    onSelected: _setQuickFilter,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: txs.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _refreshCurrentHistory,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.25,
                                child: EmptyState(
                                  icon: Icons.fact_check_outlined,
                                  title: _emptyTitle(user.role),
                                  message: _emptyMessage(user.role),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshCurrentHistory,
                          child: ListView.builder(
                            controller: acpec ? _scroll : null,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: groups.length +
                                (acpec && _acpecError != null ? 1 : 0) +
                                (acpec ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (acpec && _acpecError != null && i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: BackendUnavailableBanner(
                                    message: _acpecError!,
                                    onRetry: () {
                                      unawaited(_reloadAcpecForCurrentFilter());
                                    },
                                  ),
                                );
                              }
                              final groupIndex =
                                  i - (acpec && _acpecError != null ? 1 : 0);
                              if (acpec && groupIndex == groups.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      if (_acpecHasMore &&
                                          !_acpecLoadingMore &&
                                          _acpecItems.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _loadAcpec(reset: false),
                                            icon: const Icon(
                                              Icons.expand_more_rounded,
                                              size: 20,
                                            ),
                                            label: const Text(
                                              'Charger la page suivante',
                                            ),
                                          ),
                                        ),
                                      Center(
                                        child: _acpecLoadingMore
                                            ? SizedBox(
                                                width: 220,
                                                child: AppLoadingSkeleton(
                                                  style: AppLoadingSkeletonStyle
                                                      .historyRows,
                                                  itemCount: 1,
                                                ),
                                              )
                                            : _acpecHasMore
                                            ? Text(
                                                'Faites d\u00e9filer pour charger plus',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted
                                                      .withValues(alpha: 0.9),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            : Text(
                                                "Fin de l'historique pour cette période",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted
                                                      .withValues(alpha: 0.85),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final g = groups[groupIndex];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: groupIndex == 0 ? 0 : 18,
                                    ),
                                    child: Text(
                                      g.label.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.85,
                                        color: AppColors.muted.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  for (final t in g.items) ...[
                                    _TxCard(tx: t),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<({String label, List<BusinessTransaction> items})> _groupByDay(
    List<BusinessTransaction> txs,
  ) {
    final map = <String, List<BusinessTransaction>>{};
    final today = DateTime.now();
    for (final t in txs) {
      final key = _dayLabel(t.date, today);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map.entries.map((e) => (label: e.key, items: e.value)).toList();
  }

  String _dayLabel(DateTime d, DateTime today) {
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    if (isToday) return 'Aujourd\'hui';
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday =
        d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day;
    if (isYesterday) return 'Hier';
    return Formatters.date(d);
  }
}

class _TxCard extends StatefulWidget {
  const _TxCard({required this.tx});

  final BusinessTransaction tx;

  @override
  State<_TxCard> createState() => _TxCardState();
}

class _TxCardState extends State<_TxCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final amountColor = _historyAmountColor(tx.type);
    final title = tx.displayTitle;
    final dateLabel = DateFormat('dd-MM-yyyy').format(tx.date);
    final hourLabel = DateFormat('HH:mm:ss').format(tx.date);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAED)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionPanelList(
          expandedHeaderPadding: EdgeInsets.zero,
          elevation: 0,
          materialGapSize: 0,
          expansionCallback: (panelIndex, isExpanded) {
            setState(() => _expanded = !_expanded);
          },
          children: [
            ExpansionPanel(
              canTapOnHeader: true,
              backgroundColor: Colors.transparent,
              isExpanded: _expanded,
              headerBuilder: (context, isExpanded) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _AmountInline(
                            amount: tx.totalAmount.abs(),
                            textAlign: TextAlign.right,
                            valueStyle: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: amountColor,
                              height: 1,
                              letterSpacing: -0.2,
                            ),
                            unitStyle: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: amountColor.withValues(alpha: 0.82),
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateLabel $hourLabel',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: _TxDetailBody(tx: tx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxDetailBody extends StatelessWidget {
  const _TxDetailBody({required this.tx});

  final BusinessTransaction tx;

  @override
  Widget build(BuildContext context) {
    final rows = _transactionDetailRows(tx);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _TxDetailRowWidget(row: rows[i]),
          if (i < rows.length - 1)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8EAED)),
        ],
        if (tx.lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Lignes',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.muted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < tx.lines.length; i++) ...[
            _TxLineRow(txType: tx.type, line: tx.lines[i]),
            if (i < tx.lines.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _TxDetailRow {
  const _TxDetailRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _TxDetailRowWidget extends StatelessWidget {
  const _TxDetailRowWidget({required this.row});

  final _TxDetailRow row;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              row.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TxLineRow extends StatelessWidget {
  const _TxLineRow({required this.txType, required this.line});

  final TxType txType;
  final TransactionLine line;

  bool get _isPurchaseStyle =>
      txType == TxType.purchaseSubmitted ||
      txType == TxType.purchaseValidated ||
      txType == TxType.purchaseRejected ||
      txType == TxType.carnetTransfer ||
      txType == TxType.carnetReceived;

  bool get _isQrStyle =>
      txType == TxType.stationConsumption ||
      txType == TxType.qrEmission ||
      txType == TxType.qrSeparer ||
      txType == TxType.qrRetirer ||
      txType == TxType.qrBlocked ||
      txType == TxType.expiration;

  int _carnetSize({required bool fromAmount}) {
    if (line.carnetSize > 0) return line.carnetSize;
    if (!fromAmount ||
        line.faceValue <= 0 ||
        line.qty <= 0 ||
        line.amount <= 0) {
      return 0;
    }
    final derived = (line.amount / line.faceValue / line.qty).round();
    return derived > 0 ? derived : 0;
  }

  String _purchaseTitle() {
    final serverLabel = line.carnetTypeName.trim();
    if (serverLabel.isNotEmpty) return serverLabel;
    if (line.carnetSize > 0 && line.faceValue > 0) {
      return _historyCarnetTypeLabel(line.carnetSize, line.faceValue);
    }
    final carnetSize = _carnetSize(fromAmount: true);
    if (carnetSize > 0 && line.faceValue > 0) {
      return _historyCarnetTypeLabel(carnetSize, line.faceValue);
    }
    if (line.faceValue > 0) {
      return 'Carnet ${Formatters.numberFr(line.faceValue)}';
    }
    return 'Carnet';
  }

  String _lineTypeLabel() {
    final label = _purchaseTitle();
    if (label.trim().isNotEmpty) return label;
    return 'Carnet';
  }

  String _qrTitle() {
    final qty = line.qty > 0 ? line.qty : 1;
    final ticketLabel =
        '${Formatters.numberFr(qty)} ticket${qty > 1 ? 's' : ''}';
    final carnetLabel = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackSize: line.carnetSize,
      fallbackFaceValue: line.faceValue,
      fallbackCode: line.carnetTypeCode,
    ).replaceFirst(RegExp(r'^Carnet\s+', caseSensitive: false), 'carnet ');
    return '$ticketLabel de $carnetLabel';
  }

  String? _subtitle() {
    if (txType == TxType.purchaseSubmitted) return null;
    if (line.expirationDate == null) return null;
    return 'Date d\'expiration : ${DateFormat('dd-MM-yyyy').format(line.expirationDate!)}';
  }

  TextStyle _titleStyle(BuildContext context, {required double fontSize}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
      height: 1.15,
    );
  }

  TextStyle _dateStyle() {
    return const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
      height: 1.25,
    );
  }

  Widget _purchaseBody(BuildContext context) {
    final subtitle = _subtitle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lineTypeLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(context, fontSize: 14),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: _dateStyle()),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AmountInline(
            amount: line.amount,
            textAlign: TextAlign.right,
            valueStyle: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.1,
            ),
            unitStyle: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.82),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrBody(BuildContext context) {
    final subtitle = _subtitle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _qrTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(context, fontSize: 14),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: _dateStyle()),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AmountInline(
            amount: line.amount,
            textAlign: TextAlign.right,
            valueStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.1,
            ),
            unitStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.72),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPurchaseStyle) return _purchaseBody(context);
    if (_isQrStyle) return _qrBody(context);
    return _qrBody(context);
  }
}

List<_TxDetailRow> _transactionDetailRows(BusinessTransaction tx) {
  final lotRef = tx.lotInternalRef ?? tx.lotId;
  final qrRef = tx.qrPublicCode ?? tx.qrId;
  final station = tx.stationName ?? tx.stationId;
  final totalQty = tx.lines.fold<int>(0, (sum, l) => sum + l.qty);

  switch (tx.type) {
    case TxType.purchaseSubmitted:
    case TxType.purchaseValidated:
    case TxType.purchaseRejected:
      return [
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: 'Carnet', value: lotRef),
        _TxDetailRow(label: 'Acheteur', value: tx.userName),
        if (tx.type == TxType.purchaseSubmitted &&
            (tx.note ?? '').trim().isNotEmpty)
          _TxDetailRow(label: 'Note', value: tx.note!.trim()),
        if (tx.type == TxType.purchaseRejected &&
            (tx.note ?? '').trim().isNotEmpty)
          _TxDetailRow(label: 'Message', value: tx.note!.trim()),
      ];
    case TxType.qrEmission:
      return [
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'Code QR', value: qrRef),
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: 'Carnet', value: lotRef),
      ];
    case TxType.qrSeparer:
      return [
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'QR', value: qrRef),
        _TxDetailRow(label: 'Tickets', value: '$totalQty'),
      ];
    case TxType.qrRetirer:
      return [
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'Code QR', value: qrRef),
        _TxDetailRow(label: 'Tickets retirés', value: '$totalQty'),
      ];
    case TxType.carnetTransfer:
      return [
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: 'Carnet', value: lotRef),
        if ((tx.transferParty ?? '').trim().isNotEmpty)
          _TxDetailRow(label: 'Receveur', value: tx.transferParty!.trim()),
        if ((tx.transferPartyPhone ?? '').trim().isNotEmpty)
          _TxDetailRow(
            label: 'Téléphone receveur',
            value: tx.transferPartyPhone!.trim(),
          ),
      ];
    case TxType.carnetReceived:
      return [
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: 'Carnet', value: lotRef),
        if ((tx.transferParty ?? '').trim().isNotEmpty)
          _TxDetailRow(label: 'Envoyeur', value: tx.transferParty!.trim()),
        if ((tx.transferPartyPhone ?? '').trim().isNotEmpty)
          _TxDetailRow(
            label: 'Téléphone envoyeur',
            value: tx.transferPartyPhone!.trim(),
          ),
      ];
    case TxType.stationConsumption:
      return [
        if (station != null && station.isNotEmpty)
          _TxDetailRow(label: 'Station', value: station),
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'Code QR', value: qrRef),
      ];
    case TxType.expiration:
      return [
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'Code QR', value: qrRef),
      ];
    case TxType.qrBlocked:
    case TxType.walletLedger:
      return [
        if (qrRef != null && qrRef.isNotEmpty)
          _TxDetailRow(label: 'Code QR', value: qrRef),
        if (tx.type == TxType.qrBlocked)
          const _TxDetailRow(
            label: 'Message',
            value: 'QR bloqué a cause des tickets expirés',
          )
        else if ((tx.note ?? '').trim().isNotEmpty)
          _TxDetailRow(label: 'Message', value: tx.note!.trim()),
      ];
  }
}

String historyTxTitle(TxType type) {
  switch (type) {
    case TxType.purchaseSubmitted:
      return 'Achat en attente';
    case TxType.purchaseValidated:
      return 'Achat validé';
    case TxType.purchaseRejected:
      return 'Achat rejeté';
    case TxType.qrEmission:
      return 'QR prêt';
    case TxType.qrSeparer:
      return 'Partage du QR';
    case TxType.qrRetirer:
      return 'Retrait du QR';
    case TxType.carnetTransfer:
      return 'Carnets envoyés';
    case TxType.carnetReceived:
      return 'Carnets reçus';
    case TxType.qrBlocked:
      return 'QR bloqué';
    case TxType.stationConsumption:
      return 'Utilisation en station';
    case TxType.expiration:
      return 'Fin de validité';
    case TxType.walletLedger:
      return 'Mouvement';
  }
}

Color _historyAmountColor(TxType type) {
  switch (type) {
    case TxType.purchaseValidated:
      return AppColors.leaderGreen;
    case TxType.carnetReceived:
      return AppColors.leaderGreen;
    case TxType.purchaseSubmitted:
    case TxType.purchaseRejected:
      return AppColors.danger;
    case TxType.carnetTransfer:
    case TxType.stationConsumption:
    case TxType.expiration:
      return AppColors.danger;
    case TxType.qrBlocked:
    case TxType.qrEmission:
    case TxType.qrSeparer:
    case TxType.qrRetirer:
    case TxType.walletLedger:
      return AppColors.primary;
  }
}

class _HistoryFilterChips extends StatelessWidget {
  const _HistoryFilterChips({required this.selected, required this.onSelected});

  final _HistoryQuickFilter selected;
  final ValueChanged<_HistoryQuickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_HistoryQuickFilter.all, 'Tous'),
      (_HistoryQuickFilter.purchases, 'Achats'),
      (_HistoryQuickFilter.transfer, 'Envoi / reçu'),
      (_HistoryQuickFilter.consumption, 'Consommation'),
      (_HistoryQuickFilter.qr, 'QR'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _HistoryFilterChip(
              label: items[i].$2,
              selected: selected == items[i].$1,
              onTap: () => onSelected(items[i].$1),
            ),
            if (i != items.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _HistoryFilterChip extends StatelessWidget {
  const _HistoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

String _historyCarnetTypeLabel(int size, int faceValue) {
  return 'Carnet ${Formatters.numberFr(size)} x $faceValue';
}

class _TransactionFact {
  const _TransactionFact({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _AmountInline extends StatelessWidget {
  const _AmountInline({
    required this.amount,
    required this.valueStyle,
    required this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final label = Formatters.money(amount);
    return Semantics(
      label: label,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
            TextSpan(text: ' ${Formatters.defaultCurrency}', style: unitStyle),
          ],
        ),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ignore: unused_element
List<_TransactionFact> _transactionFacts(BusinessTransaction tx) {
  final green = const Color(0xFF1B8F3A);
  final amber = const Color(0xFFF59E0B);
  final blue = const Color(0xFF2563EB);
  final violet = const Color(0xFF7C3AED);
  final gray = AppColors.muted;
  final totalQty = tx.lines.fold<int>(0, (sum, l) => sum + l.qty);
  final lineCount = tx.lines.length;
  final qr = tx.qrPublicCode ?? tx.qrId;
  final lotRef = tx.lotInternalRef ?? tx.lotId;
  final station = tx.stationName ?? tx.stationId;
  final client = tx.userName.trim().isNotEmpty ? tx.userName : tx.userId;
  final amount = Formatters.money(tx.totalAmount.abs());

  switch (tx.type) {
    case TxType.purchaseSubmitted:
    case TxType.purchaseValidated:
    case TxType.purchaseRejected:
      return [
        _TransactionFact(
          label: 'Carnet',
          value: lotRef ?? '—',
          icon: Icons.shopping_bag_outlined,
          color: green,
        ),
        _TransactionFact(
          label: 'Acheteur',
          value: client,
          icon: Icons.person_outline_rounded,
          color: blue,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
    case TxType.qrEmission:
      return [
        _TransactionFact(
          label: 'Code QR',
          value: qr ?? '—',
          icon: Icons.qr_code_2_outlined,
          color: green,
        ),
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.confirmation_number_outlined,
          color: amber,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: blue,
        ),
        if (lotRef != null)
          _TransactionFact(
            label: 'Carnet',
            value: lotRef,
            icon: Icons.receipt_long_outlined,
            color: gray,
          ),
      ];
    case TxType.qrSeparer:
      return [
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.call_split_rounded,
          color: violet,
        ),
        _TransactionFact(
          label: 'Parties',
          value: '$lineCount',
          icon: Icons.view_list_rounded,
          color: gray,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
    case TxType.qrRetirer:
      return [
        _TransactionFact(
          label: 'Tickets retirés',
          value: '$totalQty',
          icon: Icons.remove_circle_outline_rounded,
          color: amber,
        ),
        _TransactionFact(
          label: 'Parties',
          value: '$lineCount',
          icon: Icons.view_list_rounded,
          color: gray,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
    case TxType.carnetTransfer:
      return [
        _TransactionFact(
          label: 'Carnet',
          value: lotRef ?? '—',
          icon: Icons.swap_horiz_rounded,
          color: blue,
        ),
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.inventory_2_outlined,
          color: violet,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
        _TransactionFact(
          label: 'Receveur',
          value: client,
          icon: Icons.person_outline_rounded,
          color: gray,
        ),
        if ((tx.transferPartyPhone ?? '').trim().isNotEmpty)
          _TransactionFact(
            label: 'Téléphone receveur',
            value: tx.transferPartyPhone!.trim(),
            icon: Icons.phone_outlined,
            color: gray,
          ),
      ];
    case TxType.carnetReceived:
      return [
        _TransactionFact(
          label: 'Carnet',
          value: lotRef ?? '—',
          icon: Icons.swap_horiz_rounded,
          color: blue,
        ),
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.inventory_2_outlined,
          color: violet,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
        _TransactionFact(
          label: 'Envoyeur',
          value: tx.transferParty?.trim().isNotEmpty == true
              ? tx.transferParty!.trim()
              : client,
          icon: Icons.person_outline_rounded,
          color: gray,
        ),
        if ((tx.transferPartyPhone ?? '').trim().isNotEmpty)
          _TransactionFact(
            label: 'Téléphone envoyeur',
            value: tx.transferPartyPhone!.trim(),
            icon: Icons.phone_outlined,
            color: gray,
          ),
      ];
    case TxType.qrBlocked:
      return [
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.confirmation_number_outlined,
          color: gray,
        ),
        _TransactionFact(
          label: 'Message',
          value: 'QR bloqué a cause des tickets expirés',
          icon: Icons.info_outline_rounded,
          color: blue,
        ),
      ];
    case TxType.stationConsumption:
      return [
        _TransactionFact(
          label: 'Station',
          value: station ?? '—',
          icon: Icons.local_gas_station_outlined,
          color: green,
        ),
        _TransactionFact(
          label: 'Tickets',
          value: '$totalQty',
          icon: Icons.water_drop_outlined,
          color: amber,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
    case TxType.expiration:
      return [
        _TransactionFact(
          label: 'Code QR',
          value: qr ?? '—',
          icon: Icons.hourglass_bottom_rounded,
          color: amber,
        ),
        _TransactionFact(
          label: 'Tickets expirés',
          value: '$totalQty',
          icon: Icons.block_outlined,
          color: gray,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
    case TxType.walletLedger:
      return [
        _TransactionFact(
          label: 'Carnet',
          value: lotRef ?? '—',
          icon: Icons.receipt_long_rounded,
          color: gray,
        ),
        _TransactionFact(
          label: 'Montant',
          value: amount,
          icon: Icons.payments_outlined,
          color: green,
        ),
      ];
  }
}
