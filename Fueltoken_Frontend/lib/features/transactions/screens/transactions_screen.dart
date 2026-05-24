import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/models/user_role.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _HistoryQuickFilter { all, activeBlocked, purchases, consumption }

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

  DateTime _draftFrom = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _draftTo = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _activeFrom = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _activeTo = DateTime.fromMillisecondsSinceEpoch(0);

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
    final now = DateTime.now();
    _draftFrom = DateTime(now.year, 1, 1);
    _draftTo = DateTime(now.year, 12, 31, 23, 59, 59);
    _activeFrom = _draftFrom;
    _activeTo = _draftTo;
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

  /// Route 5.6 : uniquement date_from, date_to, limit, offset (pas de filtre type côté API).
  Map<String, dynamic> _clientTxParams({
    required int limit,
    required int offset,
  }) {
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');
    return {
      'date_from': df.format(_activeFrom),
      'date_to': df.format(_activeTo),
      'limit': limit,
      'offset': offset,
    };
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
      case _HistoryQuickFilter.activeBlocked:
        return t.type == TxType.qrEmission ||
            t.type == TxType.qrSplit ||
            t.type == TxType.qrBlocked;
      case _HistoryQuickFilter.purchases:
        return t.type == TxType.purchaseValidated ||
            t.type == TxType.purchaseSubmitted ||
            t.type == TxType.purchaseRejected;
      case _HistoryQuickFilter.consumption:
        return t.type == TxType.stationConsumption;
    }
  }

  void _setQuickFilter(_HistoryQuickFilter next) {
    if (_quickFilter == next) return;
    setState(() => _quickFilter = next);
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
        _acpecItems = [];
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
            : e.message;
        if (reset) _acpecItems = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecLoadingMore = false;
        _acpecError = e.toString().replaceFirst('Exception: ', '');
        if (reset) _acpecItems = [];
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
        _acpecItems = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecLoading = false;
        _acpecError = e.toString().replaceFirst('Exception: ', '');
        _acpecItems = [];
      });
    }
  }

  Future<void> _reloadAcpecForCurrentFilter() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    if (_effectiveFilter == null) {
      await _loadAcpec(reset: true);
    } else {
      await _loadAcpecFullRange();
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draftFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _draftFrom = picked);
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draftTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _draftTo = picked);
    }
  }

  void _applyDateFilter() {
    final from = DateTime(_draftFrom.year, _draftFrom.month, _draftFrom.day);
    final to = DateTime(
      _draftTo.year,
      _draftTo.month,
      _draftTo.day,
      23,
      59,
      59,
    );
    setState(() {
      _activeFrom = from;
      _activeTo = to;
    });
    unawaited(_reloadAcpecForCurrentFilter());
  }

  static String _titleForRole(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Historique des transactions';
      case UserRole.station:
        return 'Journal station';
      case UserRole.admin:
        return "Journal d'activité";
    }
  }

  static String _emptyTitle(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Aucun mouvement pour l\u0027instant';
      case UserRole.station:
        return 'Aucune activité enregistrée';
      case UserRole.admin:
        return 'Journal vide';
    }
  }

  static String _emptyMessage(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Vos achats, \u00e9missions QR, partages et consommations appara\u00eetront ici d\u00e8s qu\u0027ils existeront.';
      case UserRole.station:
        return 'Les scans et consommations trait\u00e9s pour cette station s\u0027afficheront ici.';
      case UserRole.admin:
        return 'Synchronisez ou ajoutez des donn\u00e9es : le journal global se remplira automatiquement.';
    }
  }

  Future<void> _openTransactionDetail(
    BuildContext context,
    UserRole role,
    BusinessTransaction summary,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AppEnvironment.useAcpecLiveData || role != UserRole.user) {
      if (!context.mounted) return;
      await _showTransactionDetailSheet(context, summary);
      return;
    }
    final transactionId = int.tryParse(summary.id.trim());
    if (transactionId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('D\u00e9tail indisponible pour cette op\u00e9ration.'),
        ),
      );
      if (!context.mounted) return;
      await _showTransactionDetailSheet(context, summary);
      return;
    }

    var loaded = summary;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const _TransactionDetailLoadingDialog(),
      ),
    );
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) {
        loaded = summary;
      } else {
        final raw = await OdooFueltokenFacade().transactionsDetail({
          'transaction_id': transactionId,
        });
        loaded = AcpecTransactionsMapper.parseDetail(
          raw,
          userId: user.id,
          userName: user.name,
        );
      }
    } on OdooJsonRpcException catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      loaded = summary;
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      loaded = summary;
    } finally {
      if (context.mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }

    if (!context.mounted) return;
    await _showTransactionDetailSheet(context, loaded);
  }

  Future<void> _showTransactionDetailSheet(
    BuildContext context,
    BusinessTransaction tx,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.48,
          minChildSize: 0.34,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.type.label,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                Formatters.dateTime(tx.date),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: scheme.outline.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottom),
                      children: [
                        Text(
                          'D\u00e9tail des tickets',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...tx.lines.map((l) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.outline.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                children: [
                                  FaceValueChip(value: l.faceValue),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${l.qty} ticket${l.qty > 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${Formatters.numberFr(l.amount)} MRU',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.primarySoft),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              Text(
                                '${Formatters.numberFr(tx.totalAmount)} MRU',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDeep,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
                          style: GoogleFonts.inter(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filtre de date',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Flexible(
                            flex: 43,
                            child: _DateFilterChip(
                              label: 'Du',
                              value: _compactDate(_draftFrom),
                              onTap: _pickFrom,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            flex: 43,
                            child: _DateFilterChip(
                              label: 'Au',
                              value: _compactDate(_draftTo),
                              onTap: _pickTo,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Material(
                            color: const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: _applyDateFilter,
                              borderRadius: BorderRadius.circular(14),
                              child: const SizedBox(
                                width: 44,
                                height: 46,
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 24,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: txs.isEmpty
                      ? RefreshIndicator(
                          onRefresh: () async {
                            if (acpec) {
                              await _reloadAcpecForCurrentFilter();
                            } else {
                              setState(() {});
                            }
                          },
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
                          onRefresh: () async {
                            if (acpec) {
                              await _reloadAcpecForCurrentFilter();
                            } else {
                              setState(() {});
                            }
                          },
                          child: ListView.builder(
                            controller: acpec ? _scroll : null,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: groups.length + (acpec ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (acpec && i == groups.length) {
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
                                                'Fin de l\'historique pour cette période',
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
                              final g = groups[i];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: i == 0 ? 0 : 18,
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
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => unawaited(
                                          _openTransactionDetail(
                                            context,
                                            user.role,
                                            t,
                                          ),
                                        ),
                                        child: _TxCard(tx: t),
                                      ),
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

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx});

  final BusinessTransaction tx;

  @override
  Widget build(BuildContext context) {
    final amountColor = _historyAmountColor(tx.type);
    final title = _historyTxTitle(tx.type);
    final dateLabel = DateFormat('dd-MM-yyyy').format(tx.date);
    final hourLabel = DateFormat('HH:mm').format(tx.date);
    final signed = tx.totalAmount < 0;
    final amountPrefix = signed ? '- ' : '+ ';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 4, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$dateLabel \u2022 $hourLabel',
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
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix${Formatters.numberFr(tx.totalAmount.abs())}',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'MRU',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2.withValues(alpha: 0.78),
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _historyTxTitle(TxType type) {
  switch (type) {
    case TxType.purchaseSubmitted:
      return 'Achats en attente';
    case TxType.purchaseValidated:
      return 'Achats validés';
    case TxType.purchaseRejected:
      return 'Achats rejetés';
    case TxType.qrEmission:
      return 'Em\u00e9ission QR';
    case TxType.qrSplit:
      return 'Split de QR';
    case TxType.qrBlocked:
      return 'QR bloqu\u00e9';
    case TxType.stationConsumption:
      return 'Consommation QR';
    case TxType.expiration:
      return 'Expiration de tickets';
    case TxType.walletLedger:
      return 'Op\u00e9ration';
  }
}

String _compactDate(DateTime date) {
  return DateFormat('dd-MM-yyyy').format(date);
}

Color _historyAmountColor(TxType type) {
  switch (type) {
    case TxType.purchaseSubmitted:
      return AppColors.warning;
    case TxType.purchaseValidated:
      return AppColors.leaderGreen;
    case TxType.purchaseRejected:
      return AppColors.danger;
    case TxType.stationConsumption:
      return const Color(0xFFD97706);
    case TxType.qrEmission:
    case TxType.qrSplit:
      return const Color(0xFFD97706);
    case TxType.qrBlocked:
    case TxType.walletLedger:
      return AppColors.ink;
    case TxType.expiration:
      return AppColors.danger;
  }
}

class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 18, color: const Color(0xFFE5E7EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterChips extends StatelessWidget {
  const _HistoryFilterChips({required this.selected, required this.onSelected});

  final _HistoryQuickFilter selected;
  final ValueChanged<_HistoryQuickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_HistoryQuickFilter.all, 'Tout transaction'),
      (_HistoryQuickFilter.activeBlocked, 'Active / Bloqu\u00e9es'),
      (_HistoryQuickFilter.purchases, 'Achats'),
      (_HistoryQuickFilter.consumption, 'Consommation'),
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
            style: GoogleFonts.inter(
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

class _TransactionDetailLoadingDialog extends StatelessWidget {
  const _TransactionDetailLoadingDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: const AppLoadingSkeleton(
          style: AppLoadingSkeletonStyle.historyRows,
          itemCount: 4,
        ),
      ),
    );
  }
}


