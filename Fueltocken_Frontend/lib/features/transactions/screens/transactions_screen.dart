import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/models/user_role.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/face_value_chip.dart';
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

  /// Types retirés de l’UI (ex. portefeuille) se comportent comme « tous ».
  TxType? get _effectiveFilter =>
      _filter == TxType.walletLedger ? null : _filter;

  static const int _pageSize = 20;

  /// Limite de sécurité pour charger tout l’historique sur une période (filtre type).
  static const int _maxPagesFullRange = 80;

  final ScrollController _scroll = ScrollController();

  late DateTime _rangeFrom;
  late DateTime _rangeTo;

  List<BusinessTransaction> _acpecItems = [];
  bool _acpecLoading = true;
  bool _acpecLoadingMore = false;
  String? _acpecError;
  bool _acpecHasMore = true;
  int? _acpecTotal;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeFrom = DateTime(now.year, 1, 1);
    _rangeTo = DateTime(now.year, 12, 31, 23, 59, 59);
    _scroll.addListener(_onAcpecScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppEnvironment.useAcpecLiveData) {
        _loadAcpec(reset: true);
      } else {
        setState(() => _acpecLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onAcpecScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Route 5.6 : uniquement `date_from`, `date_to`, `limit`, `offset` (pas de filtre type côté API).
  Map<String, dynamic> _clientTxParams({
    required int limit,
    required int offset,
  }) {
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');
    return {
      'date_from': df.format(_rangeFrom),
      'date_to': df.format(_rangeTo),
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
        return t.type == TxType.purchaseValidated;
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
      setState(() {
        if (reset) {
          _acpecItems = List<BusinessTransaction>.of(batch);
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
      if (!mounted) return;
      setState(() {
        _acpecItems = all;
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

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _rangeFrom,
        end: DateTime(_rangeTo.year, _rangeTo.month, _rangeTo.day),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rangeFrom = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeTo = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
    });
    await _reloadAcpecForCurrentFilter();
  }

  static String _titleForRole(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Historique des transactions';
      case UserRole.station:
        return 'Journal station';
      case UserRole.admin:
        return 'Journal d’activité';
    }
  }

  static String _emptyTitle(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Aucun mouvement pour l’instant';
      case UserRole.station:
        return 'Aucune activité enregistrée';
      case UserRole.admin:
        return 'Journal vide';
    }
  }

  static String _emptyMessage(UserRole role) {
    switch (role) {
      case UserRole.user:
        return 'Vos achats, émissions QR, partages et consommations apparaîtront ici dès qu’ils existeront.';
      case UserRole.station:
        return 'Les scans et consommations traitées pour cette station s’afficheront ici.';
      case UserRole.admin:
        return 'Synchronisez ou ajoutez des données : le journal global se remplira automatiquement.';
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
          content: Text('Détail indisponible pour cette opération.'),
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
        child: Center(child: AppLoadingLottie(size: 72, fit: BoxFit.contain)),
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
    final ref = _txReferenceLine(tx);
    final note = _sanitizeTxNote(tx.note);

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
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
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
                              if (ref != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  ref,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                              if (note != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  note,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
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
                          'Détail des tickets',
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
          return const Scaffold(body: AppPageLoading());
        }

        final acpec = AppEnvironment.useAcpecLiveData;

        if (!acpec) {
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    subtitle: '—',
                    onBack: () => popOrGoRoleHome(context, user.role),
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
            : visible.where((t) => t.type == _effectiveFilter).toList();

        final groups = _groupByDay(txs);

        if (acpec &&
            _acpecLoading &&
            _acpecItems.isEmpty &&
            _acpecError == null) {
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    subtitle: 'Chargement…',
                    onBack: () => popOrGoRoleHome(context, user.role),
                    leadingOnlyWhenNavigatorCanPop: true,
                  ),
                  const Expanded(child: AppPageLoading()),
                ],
              ),
            ),
          );
        }

        if (acpec && _acpecError != null && _acpecItems.isEmpty) {
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  AppBarHeader(
                    title: _titleForRole(user.role),
                    subtitle: 'Erreur',
                    onBack: () => popOrGoRoleHome(context, user.role),
                    leadingOnlyWhenNavigatorCanPop: true,
                  ),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Center(child: AppErrorLottie(size: 120)),
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
                            label: const Text('Réessayer'),
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
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (Navigator.maybeOf(context)?.canPop() ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _HistoryRoundButton(
                            icon: Icons.chevron_left_rounded,
                            onTap: () => popOrGoRoleHome(context, user.role),
                          ),
                        )
                      else
                        const SizedBox(width: 0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _titleForRole(user.role),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.1,
                              height: 1.02,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _HistoryFilterChips(
                    selected: _quickFilter,
                    onSelected: _setQuickFilter,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _PeriodSummaryCard(
                    from: _rangeFrom,
                    to: _rangeTo,
                    onPressed: acpec && user.role != UserRole.station
                        ? _pickDateRange
                        : null,
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
                                            ? const AppLoadingLottie(size: 44)
                                            : _acpecHasMore
                                            ? Text(
                                                'Faites défiler pour charger plus',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted
                                                      .withValues(alpha: 0.9),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            : Text(
                                                'Fin de l’historique pour cette période',
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

String? _sanitizeTxNote(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var s = raw.trim();
  s = s.replaceAll(
    RegExp(r'[·•]\s*(true|false)\s*$', caseSensitive: false),
    '',
  );
  s = s.replaceAll(RegExp(r'\b(true|false)\b', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.isEmpty ? null : s;
}

String? _txTicketsSummary(BusinessTransaction tx) {
  if (tx.lines.isEmpty) return null;
  return tx.lines
      .map(
        (l) =>
            '${l.qty} ticket${l.qty > 1 ? 's' : ''} · ${Formatters.numberFr(l.faceValue)} MRU',
      )
      .join(' · ');
}

String? _txReferenceLine(BusinessTransaction tx) {
  final parts = <String>[];
  final id = tx.id.trim();
  if (id.isNotEmpty &&
      id != 'false' &&
      RegExp(r'ftx|ach|qr', caseSensitive: false).hasMatch(id)) {
    parts.add(id);
  }
  final lot = tx.lotInternalRef?.trim();
  if (lot != null && lot.isNotEmpty && lot != 'false') parts.add(lot);
  final tickets = _txTicketsSummary(tx);
  if (tickets != null) parts.add(tickets);
  final qr = tx.qrPublicCode?.trim();
  if (qr != null && qr.isNotEmpty && qr != 'false') {
    parts.add(Formatters.shortPublicCode(qr));
  }
  final st = tx.stationName?.trim();
  if (st != null && st.isNotEmpty && st != 'false') parts.add(st);
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx});

  final BusinessTransaction tx;

  @override
  Widget build(BuildContext context) {
    final signed = tx.totalAmount < 0;
    final amountColor = _historyAmountColor(tx.type);
    final title = _historyTxTitle(tx.type);
    final dateLabel = DateFormat('dd-MM-yyyy HH:mm', 'fr_FR').format(tx.date);
    final amountPrefix = signed ? '- ' : '+ ';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
          ],
        ),
      ),
    );
  }
}

String _historyTxTitle(TxType type) {
  switch (type) {
    case TxType.purchaseValidated:
      return 'Achat de carnet';
    case TxType.qrEmission:
      return 'Émission QR';
    case TxType.qrSplit:
      return 'Split de QR';
    case TxType.qrBlocked:
      return 'QR bloqué';
    case TxType.stationConsumption:
      return 'Consommation QR';
    case TxType.expiration:
      return 'Expiration de tickets';
    case TxType.walletLedger:
      return 'Opération';
  }
}

Color _historyAmountColor(TxType type) {
  switch (type) {
    case TxType.purchaseValidated:
      return AppColors.leaderGreen;
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

class _HistoryRoundButton extends StatelessWidget {
  const _HistoryRoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.95)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, size: 22, color: AppColors.ink),
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
      (_HistoryQuickFilter.activeBlocked, 'Active / Bloquées'),
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
    return Material(
      color: selected ? AppColors.leaderGreen : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.leaderGreen.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodSummaryCard extends StatelessWidget {
  const _PeriodSummaryCard({
    required this.from,
    required this.to,
    required this.onPressed,
  });

  final DateTime from;
  final DateTime to;
  final VoidCallback? onPressed;

  String _rangeLabel() {
    final formatter = DateFormat('d MMM yyyy', 'fr_FR');
    return '${formatter.format(from)} — ${formatter.format(to)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.leaderGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.leaderGreen,
              size: 17,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Période sélectionnée',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _rangeLabel(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.calendar_month_rounded, size: 13),
            label: const Text('Changer la période'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.leaderGreen,
              side: BorderSide(
                color: AppColors.leaderGreen.withValues(alpha: 0.24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              textStyle: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
