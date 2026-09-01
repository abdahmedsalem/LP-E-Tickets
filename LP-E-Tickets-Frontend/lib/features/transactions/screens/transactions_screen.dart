import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_session_host.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/models/user_role.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/date_range_filter_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/list_screen_header.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';

enum TransactionsScreenMode { history, wallet }

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.mode = TransactionsScreenMode.history,
  });

  final TransactionsScreenMode mode;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _HistoryQuickFilter {
  all,
  purchases,
  transfer,
  consumption,
  qr,
  receipts,
  expirations,
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TxType? _filter;
  _HistoryQuickFilter _quickFilter = _HistoryQuickFilter.all;

  late DateTime _activeFrom;
  late DateTime _activeTo;

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
  int _lastRefreshRevision = -1;

  bool get _isWalletMode => widget.mode == TransactionsScreenMode.wallet;

  ValueNotifier<int> get _revisionNotifier => _isWalletMode
      ? WalletRefreshBus.instance.revision
      : ClientHistoryRefreshBus.instance.revision;

  static const Set<TxType> _walletTypes = {
    TxType.purchaseValidated,
    TxType.qrEmission,
    TxType.carnetTransfer,
    TxType.carnetReceived,
    TxType.expiration,
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _activeFrom = DateTime(now.year, now.month, now.day);
    _activeTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
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
      final rev = _revisionNotifier.value;
      if (rev == _lastRefreshRevision) return;
      _lastRefreshRevision = rev;
      unawaited(_reloadAcpecForCurrentFilter());
    };
    _revisionNotifier.addListener(_historyRevisionListener!);
  }

  @override
  void dispose() {
    _revisionNotifier.removeListener(_historyRevisionListener ?? () {});
    _scroll.removeListener(_onAcpecScroll);
    _scroll.dispose();
    super.dispose();
  }

  String _apiDateTime(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  /// Route 5.6 : limit, offset, date_from/date_to.
  Map<String, dynamic> _clientTxParams({
    required int limit,
    required int offset,
  }) {
    return {
      'limit': limit,
      'offset': offset,
      'date_from': _apiDateTime(_activeFrom),
      'date_to': _apiDateTime(_activeTo),
    };
  }

  Map<String, dynamic> _stationTxParams({
    required int limit,
    required int offset,
  }) => {'limit': limit, 'offset': offset};

  void _applyDateFilter(DateTimeRange range) {
    setState(() {
      _activeFrom = range.start;
      _activeTo = range.end;
      _acpecItems = [];
      _acpecHasMore = true;
      _acpecTotal = null;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    unawaited(_loadAcpec(reset: true));
  }

  bool _matchesTypeFilter(BusinessTransaction t) {
    if (_isWalletMode && !_walletTypes.contains(t.type)) {
      return false;
    }
    final f = _effectiveFilter;
    if (f == null) return true;
    return AcpecTransactionsMapper.matchesClientFilter(t, f);
  }

  bool _matchesQuickFilter(BusinessTransaction t) {
    if (_isWalletMode) {
      switch (_quickFilter) {
        case _HistoryQuickFilter.all:
          return true;
        case _HistoryQuickFilter.purchases:
          return t.type == TxType.purchaseValidated;
        case _HistoryQuickFilter.transfer:
          return t.type == TxType.carnetTransfer && !t.transferIsIncoming;
        case _HistoryQuickFilter.consumption:
          return false;
        case _HistoryQuickFilter.qr:
          return t.type == TxType.qrEmission;
        case _HistoryQuickFilter.receipts:
          return t.type == TxType.carnetReceived ||
              (t.type == TxType.carnetTransfer && t.transferIsIncoming);
        case _HistoryQuickFilter.expirations:
          return t.type == TxType.expiration;
      }
    }
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
      case _HistoryQuickFilter.receipts:
        return t.type == TxType.carnetReceived ||
            (t.type == TxType.carnetTransfer && t.transferIsIncoming);
      case _HistoryQuickFilter.expirations:
        return t.type == TxType.expiration;
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
      final lots =
          AcpecPurchasesMapper.fromRpcResult(
            raw,
            clientId: user.id,
            clientName: user.name,
            companyId: AppEnvironment.companyIdForUser(user),
          ).where((lot) {
            final d = lot.submittedAt ?? lot.createdAt;
            return !d.isBefore(_activeFrom) && !d.isAfter(_activeTo);
          }).toList();
      return AcpecTransactionsMapper.fromSubmittedPurchases(
        lots,
        userId: user.id,
        userName: user.name,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<AcpecCarnetCatalogLoadResult> _localizedCarnetCatalog(
    dynamic user,
  ) async {
    try {
      return await AcpecCarnetCatalogService.instance
          .loadMobileCatalogFacesOnly(
            companyId: AppEnvironment.companyIdForUser(user),
          );
    } catch (_) {
      return const AcpecCarnetCatalogLoadResult(types: []);
    }
  }

  List<BusinessTransaction> _localizeTransactionsWithCatalog(
    List<BusinessTransaction> transactions,
    AcpecCarnetCatalogLoadResult catalog,
  ) {
    return AcpecCarnetCatalogService.localizeTransactionsByCarnetTypes(
      transactions: transactions,
      types: catalog.types,
    );
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
        _acpecError = AppLocalizations.of(context).commonSessionRequired;
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
      final catalogFuture = _localizedCarnetCatalog(user);
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
      final catalogResult = await catalogFuture;
      if (!mounted) return;
      final batch = _localizeTransactionsWithCatalog(
        page.items,
        catalogResult,
      ).where(_matchesTypeFilter).toList();
      final submittedRaw = reset && !_isWalletMode
          ? await _submittedPurchasesHistory(user)
          : const <BusinessTransaction>[];
      final submitted = _localizeTransactionsWithCatalog(
        submittedRaw,
        catalogResult,
      );
      setState(() {
        if (reset) {
          _acpecItems = _mergeHistory(batch, submitted);
          _lastRefreshRevision = _revisionNotifier.value;
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
      if (e.requiresReLogin) {
        AuthSessionHost.instance.notifySessionExpired();
        return;
      }
      setState(() {
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = e.isOdooSessionExpired
            ? AppLocalizations.of(context).sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = ErrorPresenter.localizedMessage(context, e);
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
        _acpecError = AppLocalizations.of(context).commonSessionRequired;
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
      final catalogFuture = _localizedCarnetCatalog(user);
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
      final submittedRaw = _isWalletMode
          ? const <BusinessTransaction>[]
          : await _submittedPurchasesHistory(user);
      final catalogResult = await catalogFuture;
      final localizedAll = _localizeTransactionsWithCatalog(all, catalogResult);
      final submitted = _localizeTransactionsWithCatalog(
        submittedRaw,
        catalogResult,
      );
      if (!mounted) return;
      setState(() {
        _acpecItems = _mergeHistory(localizedAll, submitted);
        _lastRefreshRevision = _revisionNotifier.value;
        _acpecTotal = totalHint ?? all.length;
        _acpecHasMore = false;
        _acpecLoading = false;
        _acpecError = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      if (e.requiresReLogin) {
        AuthSessionHost.instance.notifySessionExpired();
        return;
      }
      setState(() {
        _acpecLoading = false;
        _acpecError = e.isOdooSessionExpired
            ? AppLocalizations.of(context).sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecError = ErrorPresenter.localizedMessage(context, e);
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

  static String _titleForRole(
    AppLocalizations l10n,
    UserRole role,
    TransactionsScreenMode mode,
  ) {
    if (mode == TransactionsScreenMode.wallet) {
      return l10n.walletMovementsTitle;
    }
    switch (role) {
      case UserRole.user:
        return l10n.transactionsHistoryTitle;
      case UserRole.station:
        return l10n.stationHistoryTitle;
      case UserRole.admin:
        return l10n.globalHistoryTitle;
    }
  }

  String _emptyTitle(
    AppLocalizations l10n,
    UserRole role,
    TransactionsScreenMode mode,
  ) {
    if (role == UserRole.user && _quickFilter != _HistoryQuickFilter.all) {
      return l10n.filteredEmptyTitle(_quickFilterLabel(l10n, _quickFilter));
    }
    if (mode == TransactionsScreenMode.wallet) {
      return l10n.walletEmptyTitle;
    }
    switch (role) {
      case UserRole.user:
        return l10n.historyEmptyTitle;
      case UserRole.station:
        return l10n.stationHistoryEmptyTitle;
      case UserRole.admin:
        return l10n.globalHistoryEmptyTitle;
    }
  }

  String _emptyMessage(
    AppLocalizations l10n,
    UserRole role,
    TransactionsScreenMode mode,
  ) {
    if (role == UserRole.user && _quickFilter != _HistoryQuickFilter.all) {
      final filter = _quickFilterLabel(l10n, _quickFilter);
      return mode == TransactionsScreenMode.wallet
          ? l10n.walletFilteredEmptyMessage(filter)
          : l10n.historyFilteredEmptyMessage(filter);
    }
    if (mode == TransactionsScreenMode.wallet) {
      return l10n.walletEmptyMessage;
    }
    switch (role) {
      case UserRole.user:
        return l10n.historyEmptyMessage;
      case UserRole.station:
        return l10n.stationHistoryEmptyMessage;
      case UserRole.admin:
        return l10n.globalHistoryEmptyMessage;
    }
  }

  String _quickFilterLabel(AppLocalizations l10n, _HistoryQuickFilter filter) {
    if (_isWalletMode) {
      return switch (filter) {
        _HistoryQuickFilter.all => l10n.filterAll,
        _HistoryQuickFilter.purchases => l10n.filterPurchases,
        _HistoryQuickFilter.qr => l10n.filterQrGenerations,
        _HistoryQuickFilter.transfer => l10n.filterTransfers,
        _HistoryQuickFilter.receipts => l10n.filterReceipts,
        _HistoryQuickFilter.expirations => l10n.filterExpirations,
        _HistoryQuickFilter.consumption => l10n.filterConsumption,
      };
    }
    return switch (filter) {
      _HistoryQuickFilter.all => l10n.filterAll,
      _HistoryQuickFilter.purchases => l10n.filterOrders,
      _HistoryQuickFilter.transfer => l10n.filterSentReceived,
      _HistoryQuickFilter.consumption => l10n.filterConsumption,
      _HistoryQuickFilter.qr => l10n.navQr,
      _HistoryQuickFilter.receipts => l10n.filterReceipts,
      _HistoryQuickFilter.expirations => l10n.filterExpirations,
    };
  }

  Widget _listHeader(AppLocalizations l10n, UserRole role) {
    final filters = _isWalletMode
        ? const [
            _HistoryQuickFilter.all,
            _HistoryQuickFilter.purchases,
            _HistoryQuickFilter.qr,
            _HistoryQuickFilter.transfer,
            _HistoryQuickFilter.receipts,
            _HistoryQuickFilter.expirations,
          ]
        : const [
            _HistoryQuickFilter.all,
            _HistoryQuickFilter.purchases,
            _HistoryQuickFilter.transfer,
            _HistoryQuickFilter.consumption,
            _HistoryQuickFilter.qr,
          ];
    final options = [
      for (final filter in filters)
        ListScreenFilterOption(
          value: filter,
          label: _quickFilterLabel(l10n, filter),
        ),
    ];

    return ListScreenHeader<_HistoryQuickFilter>(
      title: _titleForRole(l10n, role, widget.mode),
      options: options,
      selected: _quickFilter,
      onSelected: _setQuickFilter,
    );
  }

  Widget _headerForState(AppLocalizations l10n, UserRole role) {
    if (role == UserRole.user) return _listHeader(l10n, role);
    return AppBarHeader(
      title: _titleForRole(l10n, role, widget.mode),
      onBack: () => popOrGoRoleHome(context, role),
      showBack: true,
      leadingOnlyWhenNavigatorCanPop: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final l10n = AppLocalizations.of(context);
        final user = authState.user;
        if (user == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  _listHeader(l10n, UserRole.user),
                  Expanded(
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
                      children: const [
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

        final acpec = AppEnvironment.useAcpecLiveData;
        final currentUserId = user.id;

        if (!acpec) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  _headerForState(l10n, user.role),
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
        final groups = _groupByDay(txs, l10n);

        if (acpec && _acpecLoading && _acpecError == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  _headerForState(l10n, user.role),
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
                  _headerForState(l10n, user.role),
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
                            label: Text(l10n.commonRetry),
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
                _listHeader(l10n, user.role),
                if (user.role == UserRole.user) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DateRangeFilterBar(
                      initialFrom: _activeFrom,
                      initialTo: _activeTo,
                      onApply: _applyDateFilter,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: txs.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _refreshCurrentHistory,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: [
                              EmptyState(
                                icon: Icons.fact_check_outlined,
                                title: _emptyTitle(
                                  l10n,
                                  user.role,
                                  widget.mode,
                                ),
                                message: _emptyMessage(
                                  l10n,
                                  user.role,
                                  widget.mode,
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
                            itemCount:
                                groups.length +
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
                                            label: Text(l10n.loadNextPage),
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
                                                l10n.scrollToLoadMore,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted
                                                      .withValues(alpha: 0.9),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            : Text(
                                                l10n.historyPeriodEnd,
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
                                    _TxCard(
                                      tx: t,
                                      currentUserId: currentUserId,
                                      mode: widget.mode,
                                    ),
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
    AppLocalizations l10n,
  ) {
    final map = <String, List<BusinessTransaction>>{};
    final today = DateTime.now();
    for (final t in txs) {
      final key = _dayLabel(t.date, today, l10n);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map.entries.map((e) => (label: e.key, items: e.value)).toList();
  }

  String _dayLabel(DateTime d, DateTime today, AppLocalizations l10n) {
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    if (isToday) return l10n.today;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday =
        d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day;
    if (isYesterday) return l10n.yesterday;
    return Formatters.date(d);
  }
}

class _TxCard extends StatefulWidget {
  const _TxCard({
    required this.tx,
    required this.currentUserId,
    required this.mode,
  });

  final BusinessTransaction tx;
  final String currentUserId;
  final TransactionsScreenMode mode;

  @override
  State<_TxCard> createState() => _TxCardState();
}

class _TxCardState extends State<_TxCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final l10n = AppLocalizations.of(context);
    final amountColor = _amountColorFor(
      tx,
      mode: widget.mode,
      currentUserId: widget.currentUserId,
    );
    final title = _transactionTitle(
      l10n,
      tx,
      widget.currentUserId,
      mode: widget.mode,
    );
    final dateLabel = DateFormat('dd-MM-yyyy').format(tx.date);
    final hourLabel = DateFormat('HH:mm:ss').format(tx.date);
    final amountPrefix = _historyAmountPrefix(
      tx,
      mode: widget.mode,
      currentUserId: widget.currentUserId,
    );
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
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SingleLineCardTitle(
                              text: title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 12),
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
                      ),
                      const SizedBox(width: 12),
                      _AmountInline(
                        amount: tx.totalAmount.abs(),
                        prefix: amountPrefix,
                        textAlign: TextAlign.end,
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
                );
              },
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: _TxDetailBody(
                  tx: tx,
                  currentUserId: widget.currentUserId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxDetailBody extends StatelessWidget {
  const _TxDetailBody({required this.tx, required this.currentUserId});

  final BusinessTransaction tx;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _transactionDetailRows(l10n, tx, currentUserId);
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
            l10n.detail,
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
              textAlign: TextAlign.end,
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

  String _purchaseTitle(AppLocalizations l10n) {
    final serverLabel = line.carnetTypeName.trim();
    if (serverLabel.isNotEmpty) return serverLabel;
    final code = line.carnetTypeCode.trim();
    if (code.isNotEmpty) return code;
    return l10n.carnet;
  }

  String _lineTypeLabel(AppLocalizations l10n) {
    final label = _purchaseTitle(l10n);
    if (label.trim().isNotEmpty) return label;
    return l10n.carnet;
  }

  String _qrTitle(AppLocalizations l10n) {
    final qty = line.qty > 0 ? line.qty : 1;
    final resolvedLabel = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    final carnetLabel = resolvedLabel.isNotEmpty ? resolvedLabel : l10n.carnet;
    return l10n.ticketsFromCarnet(qty, carnetLabel);
  }

  String? _subtitle(AppLocalizations l10n) {
    if (txType == TxType.purchaseSubmitted) return null;
    if (line.expirationDate == null) return null;
    return l10n.expirationDateLabel(
      DateFormat('dd-MM-yyyy').format(line.expirationDate!),
    );
  }

  bool get _showTicketCount =>
      (txType == TxType.carnetTransfer || txType == TxType.carnetReceived) &&
      line.qty > 0;

  String? _ticketCountLabel(AppLocalizations l10n) {
    if (!_showTicketCount) return null;
    return l10n.ticketCount(line.qty);
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
    final l10n = AppLocalizations.of(context);
    final subtitle = _subtitle(l10n);
    final ticketCountLabel = _ticketCountLabel(l10n);
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
                SingleLineCardTitle(
                  text: _lineTypeLabel(l10n),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AmountInline(
                amount: line.amount,
                textAlign: TextAlign.end,
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
              if (ticketCountLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  ticketCountLabel,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    height: 1.15,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _qrBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitle = _subtitle(l10n);
    final ticketCountLabel = _ticketCountLabel(l10n);
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
                SingleLineCardTitle(
                  text: _qrTitle(l10n),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AmountInline(
                amount: line.amount,
                textAlign: TextAlign.end,
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
              if (ticketCountLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  ticketCountLabel,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    height: 1.15,
                  ),
                ),
              ],
            ],
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

List<_TxDetailRow> _transactionDetailRows(
  AppLocalizations l10n,
  BusinessTransaction tx,
  String currentUserId,
) {
  final qrReference = tx.qrName ?? tx.qrPublicCode ?? tx.qrId ?? '';
  final lotRef = tx.lotInternalRef ?? tx.lotId;
  final station = tx.stationName ?? tx.stationId;
  final totalQty = tx.lines.fold<int>(0, (sum, l) => sum + l.qty);
  final transferPartyLabel = tx.isIncomingTransferForViewer(currentUserId)
      ? l10n.sender
      : l10n.beneficiary;
  final pendingPurchaseDecision = switch (tx.pendingPurchaseDecisionLabel) {
    'Commande validée' => l10n.orderValidatedNote,
    'Commande refusée' => l10n.orderRejectedNote,
    _ => null,
  };
  final baseRows = <_TxDetailRow>[
    _TxDetailRow(
      label: l10n.publicReference,
      value: tx.txReference?.trim().isNotEmpty == true
          ? tx.txReference!.trim()
          : tx.txNumber,
    ),
  ];

  switch (tx.type) {
    case TxType.purchaseSubmitted:
    case TxType.purchaseValidated:
    case TxType.purchaseRejected:
      return [
        ...baseRows,
        if (tx.type != TxType.purchaseValidated &&
            lotRef != null &&
            lotRef.isNotEmpty)
          _TxDetailRow(label: l10n.carnet, value: lotRef),
        _TxDetailRow(label: l10n.buyer, value: tx.userName),
        if (tx.type == TxType.purchaseRejected &&
            (tx.note ?? '').trim().isNotEmpty)
          _TxDetailRow(label: l10n.rejectionReason, value: tx.note!.trim())
        else if (pendingPurchaseDecision != null)
          _TxDetailRow(label: l10n.note, value: pendingPurchaseDecision),
      ];
    case TxType.qrEmission:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: l10n.carnet, value: lotRef),
      ];
    case TxType.qrSeparer:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
        _TxDetailRow(label: l10n.tickets, value: '$totalQty'),
      ];
    case TxType.qrRetirer:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
        _TxDetailRow(label: l10n.withdrawnTickets, value: '$totalQty'),
      ];
    case TxType.carnetTransfer:
      {
        return [
          ...baseRows,
          if (lotRef != null && lotRef.isNotEmpty)
            _TxDetailRow(label: l10n.carnet, value: lotRef),
          if ((tx.transferParty ?? '').trim().isNotEmpty)
            _TxDetailRow(
              label: transferPartyLabel,
              value: tx.transferParty!.trim(),
            ),
        ];
      }
    case TxType.carnetReceived:
      return [
        ...baseRows,
        if (lotRef != null && lotRef.isNotEmpty)
          _TxDetailRow(label: l10n.carnet, value: lotRef),
        if ((tx.transferParty ?? '').trim().isNotEmpty)
          _TxDetailRow(label: l10n.sender, value: tx.transferParty!.trim()),
      ];
    case TxType.stationConsumption:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
        if (station != null && station.isNotEmpty)
          _TxDetailRow(label: l10n.station, value: station),
        if ((tx.actorUserName ?? '').trim().isNotEmpty)
          _TxDetailRow(label: l10n.attendant, value: tx.actorUserName!.trim()),
      ];
    case TxType.expiration:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
      ];
    case TxType.qrBlocked:
    case TxType.walletLedger:
      return [
        ...baseRows,
        if (qrReference.trim().isNotEmpty && tx.type == TxType.qrBlocked)
          _TxDetailRow(label: l10n.referenceCode, value: qrReference.trim()),
        if (tx.type == TxType.qrBlocked)
          _TxDetailRow(
            label: l10n.message,
            value: l10n.qrBlockedExpiredTicketsMessage,
          )
        else if ((tx.note ?? '').trim().isNotEmpty)
          _TxDetailRow(label: l10n.message, value: tx.note!.trim()),
      ];
  }
}

String _transactionTitle(
  AppLocalizations l10n,
  BusinessTransaction tx,
  String currentUserId, {
  required TransactionsScreenMode mode,
}) {
  if (tx.type == TxType.carnetTransfer || tx.type == TxType.carnetReceived) {
    final incoming = tx.isIncomingTransferForViewer(currentUserId);
    final tickets = tx.isTicketTransfer;
    if (incoming) {
      return tickets ? l10n.txTicketReceipt : l10n.txCarnetReceipt;
    }
    return tickets ? l10n.txTicketTransfer : l10n.txCarnetTransfer;
  }
  return switch (tx.type) {
    TxType.purchaseSubmitted => l10n.txOrderSubmitted,
    TxType.purchaseValidated => l10n.txOrderValidated,
    TxType.purchaseRejected => l10n.txOrderRejected,
    TxType.qrEmission => l10n.txQrGeneration,
    TxType.qrSeparer => l10n.txQrSplit,
    TxType.qrRetirer => l10n.txQrWithdrawal,
    TxType.qrBlocked => l10n.txQrBlocked,
    TxType.stationConsumption => l10n.txFuelConsumption,
    TxType.expiration =>
      mode == TransactionsScreenMode.wallet
          ? l10n.walletCarnetExpiration
          : l10n.txQrExpiration,
    TxType.walletLedger => l10n.txMovement,
    TxType.carnetTransfer || TxType.carnetReceived => l10n.txMovement,
  };
}

String historyTxTitle(TxType type) {
  switch (type) {
    case TxType.purchaseSubmitted:
      return 'Commande de carnets';
    case TxType.purchaseValidated:
      return 'Carnets commandés';
    case TxType.purchaseRejected:
      return 'Commande de carnets rejetée';
    case TxType.qrEmission:
      return 'Génération de QR';
    case TxType.qrSeparer:
      return 'Partage du QR';
    case TxType.qrRetirer:
      return 'Retrait du QR';
    case TxType.carnetTransfer:
      return 'Transfert';
    case TxType.carnetReceived:
      return 'Carnets reçus';
    case TxType.qrBlocked:
      return 'QR bloqué';
    case TxType.stationConsumption:
      return 'Consommation de carburant';
    case TxType.expiration:
      return 'Expiration QR';
    case TxType.walletLedger:
      return 'Mouvement';
  }
}

Color _amountColorFor(
  BusinessTransaction tx, {
  required TransactionsScreenMode mode,
  String? currentUserId,
}) {
  switch (tx.type) {
    case TxType.purchaseValidated:
      return AppColors.leaderGreen;
    case TxType.carnetTransfer:
    case TxType.carnetReceived:
      final isIncoming = tx.isIncomingTransferForViewer(currentUserId);
      return isIncoming ? AppColors.leaderGreen : AppColors.danger;
    case TxType.purchaseSubmitted:
    case TxType.purchaseRejected:
    case TxType.expiration:
    case TxType.stationConsumption:
    case TxType.qrEmission:
    case TxType.qrSeparer:
    case TxType.qrRetirer:
      return AppColors.danger;
    default:
      return AppColors.primary;
  }
}

String _historyAmountPrefix(
  BusinessTransaction tx, {
  required TransactionsScreenMode mode,
  String? currentUserId,
}) {
  if (mode != TransactionsScreenMode.wallet) return '';
  switch (tx.type) {
    case TxType.purchaseValidated:
      return '+ ';
    case TxType.carnetTransfer:
    case TxType.carnetReceived:
      final isIncoming = tx.isIncomingTransferForViewer(currentUserId);
      return isIncoming ? '+ ' : '- ';
    case TxType.expiration:
    case TxType.qrEmission:
      return '- ';
    default:
      return '';
  }
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
    this.textAlign = TextAlign.start,
    this.prefix = '',
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final label = prefix.isEmpty
        ? Formatters.money(amount)
        : '$prefix${Formatters.money(amount)}';
    return Semantics(
      label: label,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$prefix${Formatters.numberFr(amount)}',
              style: valueStyle,
            ),
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
        if (tx.type != TxType.purchaseValidated)
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
          label: 'Expéditeur',
          value: client,
          icon: Icons.person_outline_rounded,
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
          label: 'Expéditeur',
          value: tx.transferParty?.trim().isNotEmpty == true
              ? tx.transferParty!.trim()
              : client,
          icon: Icons.person_outline_rounded,
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
          value: 'QR bloqué à cause des tickets expirés',
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
        if ((tx.actorUserName ?? '').trim().isNotEmpty)
          _TransactionFact(
            label: 'Pompiste',
            value: tx.actorUserName!.trim(),
            icon: Icons.badge_outlined,
            color: gray,
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
          label: 'Code de référence QR',
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

// _transactionTitle(l10n, tx
// _transactionDetailRows(l10n, tx
