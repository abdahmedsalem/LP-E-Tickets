import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../auth/bloc/auth_bloc.dart';

enum _StationRegularizationFilter {
  pending,
  regularized,
}

extension _StationRegularizationFilterX on _StationRegularizationFilter {
  String get apiValue {
    switch (this) {
      case _StationRegularizationFilter.pending:
        return 'pending';
      case _StationRegularizationFilter.regularized:
        return 'regularized';
    }
  }

  String get label {
    switch (this) {
      case _StationRegularizationFilter.pending:
        return 'Non régularisé';
      case _StationRegularizationFilter.regularized:
        return 'Régularisé';
    }
  }

  IconData get icon {
    switch (this) {
      case _StationRegularizationFilter.pending:
        return Icons.pending_actions_rounded;
      case _StationRegularizationFilter.regularized:
        return Icons.task_alt_rounded;
    }
  }
}


class StationConsumptionHistoryScreen extends StatefulWidget {
  const StationConsumptionHistoryScreen({super.key});

  @override
  State<StationConsumptionHistoryScreen> createState() =>
      _StationConsumptionHistoryScreenState();
}

class _StationConsumptionHistoryScreenState
    extends State<StationConsumptionHistoryScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 100;
  static const int _maxAutoLoadPages = 50;
  static const Color _cOrange = Color(0xFF16A34A);

  List<BusinessTransaction> _items = [];
  bool _loading = true;
  String? _error;
  late final VoidCallback _walletBusListener;

  late DateTime _draftFrom;
  late DateTime _draftTo;
  late DateTime _activeFrom;
  late DateTime _activeTo;
  _StationRegularizationFilter _regularizationFilter =
      _StationRegularizationFilter.pending;
  late final AnimationController _skeletonCtrl;

  @override
  void initState() {
    super.initState();
    _skeletonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    final now = DateTime.now();
    _draftFrom = DateTime(now.year, now.month, now.day);
    _draftTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _activeFrom = _draftFrom;
    _activeTo = _draftTo;
    // Recharger l'historique quand un scan est effectué (WalletRefreshBus)
    _walletBusListener = () {
      if (mounted && AppEnvironment.useAcpecLiveData) _load();
    };
    WalletRefreshBus.instance.revision.addListener(_walletBusListener);
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WalletRefreshBus.instance.revision.removeListener(_walletBusListener);
    _skeletonCtrl.dispose();
    super.dispose();
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    if (ErrorPresenter.isBackendUnavailable(e)) {
      return ErrorPresenter.backendUnavailable();
    }
    return ErrorPresenter.message(e);
  }

  Future<void> _load() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Session requise.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = <BusinessTransaction>[];
      var offset = 0;
      var hasMore = true;
      var pages = 0;
      int? totalCount;

      while (hasMore && pages < _maxAutoLoadPages) {
        final raw = await OdooFueltokenFacade().stationTransactions({
          'limit': _pageSize,
          'offset': offset,
          'date_from': _apiDateTime(_activeFrom),
          'date_to': _apiDateTime(_activeTo),
          'regularization_state': _regularizationFilter.apiValue,
        });
        final page = AcpecTransactionsMapper.parsePage(
          raw,
          userId: user.id,
          userName: user.name,
          requestedLimit: _pageSize,
          requestedOffset: offset,
        );

        totalCount ??= page.totalCount;
        list.addAll(
          page.items.where((t) => t.type == TxType.stationConsumption),
        );

        pages += 1;
        offset += _pageSize;
        hasMore = page.hasMore && page.items.isNotEmpty;
      }

      list.sort((a, b) => b.date.compareTo(a.date));

      final reachedGuard = hasMore;
      final loadedCount = list.length;
      final totalKnown = totalCount;
      final partialMessage = reachedGuard
          ? totalKnown == null
                ? 'Résultat partiel : trop de consommations pour cette période. Réduisez la fenêtre de dates.'
                : 'Résultat partiel : $loadedCount / $totalKnown consommations chargées. Réduisez la fenêtre de dates.'
          : null;

      if (!mounted) return;
      setState(() {
        _items = list;
        _error = partialMessage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _briefError(e);
        _loading = false;
      });
    }
  }

  bool _matchesRegularizationFilter(BusinessTransaction tx) {
    switch (_regularizationFilter) {
      case _StationRegularizationFilter.pending:
        return !tx.isRegularized;
      case _StationRegularizationFilter.regularized:
        return tx.isRegularized;
    }
  }

  void _setRegularizationFilter(_StationRegularizationFilter filter) {
    if (_regularizationFilter == filter) return;
    setState(() {
      _regularizationFilter = filter;
    });
    if (AppEnvironment.useAcpecLiveData) {
      unawaited(_load());
    }
  }

  List<BusinessTransaction> get _filteredItems {
    return _items.where((tx) {
      if (!_matchesRegularizationFilter(tx)) return false;
      final d = tx.date;
      final start = DateTime(
        _activeFrom.year,
        _activeFrom.month,
        _activeFrom.day,
      );
      final end = DateTime(
        _activeTo.year,
        _activeTo.month,
        _activeTo.day,
        23,
        59,
        59,
      );
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
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

  void _applyFilter() {
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
    if (AppEnvironment.useAcpecLiveData) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _filteredItems;
    final shown = items;
    final totalAmount = shown.fold<int>(
      0,
      (sum, tx) => sum + tx.totalAmount.abs(),
    );
    final totalQrCount = shown.length;
    final shouldShowTotals = (!_loading && _error == null) || _items.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Relevé QR',
                subtitle: 'QR consommés par période',
                onBack: () => context.go('/station/home'),
                trailing: ScreenHeaderIconButton(
                  icon: Icons.filter_list_rounded,
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
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
                      color: _cOrange,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _applyFilter,
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
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _StationRegularizationFilterSelector(
                  selected: _regularizationFilter,
                  onSelected: _setRegularizationFilter,
                ),
              ),
              const SizedBox(height: 14),
              if (shouldShowTotals) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _StationHistoryTotalsCard(
                    totalAmount: totalAmount,
                    qrCount: totalQrCount,
                    periodLabel:
                        '${_compactDate(_activeFrom)} → ${_compactDate(_activeTo)}',
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 6),
              if (_error != null && _items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BackendUnavailableBanner(
                    message: _error!,
                    onRetry: () {
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_loading && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _HistoryLoadingSkeleton(animation: _skeletonCtrl),
                )
              else if (_error != null && _items.isEmpty)
                _ErrorPanel(message: _error!, onRetry: _load)
              else if (shown.isEmpty)
                _EmptyHistoryCard(scheme: scheme)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        _StationHistoryRow(transaction: shown[i]),
                        if (i != shown.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 18),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        color: scheme.primary,
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "C'est tout pour le moment",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aucune autre consommation enregistrée',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _compactDate(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date);
  }

  static String _apiDateTime(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF374151), width: 1.3),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 17,
              color: Color(0xFF374151),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _StationRegularizationFilterSelector extends StatelessWidget {
  const _StationRegularizationFilterSelector({
    required this.selected,
    required this.onSelected,
  });

  final _StationRegularizationFilter selected;
  final ValueChanged<_StationRegularizationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final filter in _StationRegularizationFilter.values) ...[
          Expanded(
            child: _StationRegularizationFilterChip(
              filter: filter,
              selected: selected == filter,
              onTap: () => onSelected(filter),
            ),
          ),
          if (filter != _StationRegularizationFilter.values.last)
            const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _StationRegularizationFilterChip extends StatelessWidget {
  const _StationRegularizationFilterChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _StationRegularizationFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedColor = filter == _StationRegularizationFilter.regularized
        ? const Color(0xFF16A34A)
        : const Color(0xFFEA580C);
    final fg = selected ? selectedColor : const Color(0xFF374151);
    return Material(
      color: selected
          ? selectedColor.withValues(alpha: 0.11)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? selectedColor.withValues(alpha: 0.85)
                  : scheme.outline.withValues(alpha: 0.22),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(filter.icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  filter.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _StationHistoryTotalsCard extends StatelessWidget {
  const _StationHistoryTotalsCard({
    required this.totalAmount,
    required this.qrCount,
    required this.periodLabel,
  });

  final int totalAmount;
  final int qrCount;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.summarize_rounded,
                  color: Color(0xFF16A34A),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Résumé des QR consommés',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      periodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StationHistoryTotalTile(
                  label: 'QR consommés',
                  value: Formatters.number(qrCount),
                  icon: Icons.qr_code_2_rounded,
                  valueColor: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StationHistoryTotalTile(
                  label: 'Montant total',
                  value: Formatters.money(totalAmount),
                  icon: Icons.payments_rounded,
                  valueColor: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StationHistoryTotalTile extends StatelessWidget {
  const _StationHistoryTotalTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: valueColor,
              height: 1,
              letterSpacing: -0.25,
            ),
          ),
        ],
      ),
    );
  }
}


class _StationHistoryRow extends StatelessWidget {
  const _StationHistoryRow({required this.transaction});

  final BusinessTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final amount = tx.totalAmount.abs();
    final dateLabel = DateFormat('dd-MM-yyyy').format(tx.date);
    final hourLabel = DateFormat('HH:mm:ss').format(tx.date);
    final qrTitle = tx.qrDisplayName;
    final clientLabel = tx.userName.trim().isEmpty
        ? 'Client inconnu'
        : tx.userName.trim();

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _StationConsumptionDetailScreen(
            tx: tx,
            amount: amount,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  qrTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                Formatters.money(amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  clientLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.2,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$dateLabel $hourLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsumptionDetailSummary extends StatelessWidget {
  const _ConsumptionDetailSummary({
    required this.amount,
    required this.clientName,
    required this.stationName,
    required this.txType,
  });

  final int amount;
  final String clientName;
  final String stationName;
  final String txType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_gas_station_rounded,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$stationName • $txType',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
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
                '-${Formatters.number(amount)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                Formatters.defaultCurrency,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
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

// ignore: unused_element
class _StationConsumptionDetailScreen extends StatelessWidget {
  const _StationConsumptionDetailScreen({
    required this.tx,
    required this.amount,
  });

  final BusinessTransaction tx;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.local_gas_station_rounded,
                      color: Color(0xFF16A34A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Détail QR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('dd-MM-yyyy HH:mm').format(tx.date),
                          style: TextStyle(
                            fontSize: 11,
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
            Divider(height: 1, color: scheme.outline.withValues(alpha: 0.2)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + bottom),
                children: [
                  _ConsumptionDetailSummary(
                    amount: amount,
                    clientName: tx.userName,
                    stationName: tx.qrDisplayName,
                    txType: DateFormat('dd-MM-yyyy HH:mm').format(tx.date),
                  ),
                  const SizedBox(height: 14),
                  _DetailFullWidthInfoCard(
                    label: 'N° TX',
                    value: tx.txNumber,
                  ),
                  const SizedBox(height: 10),
                  _DetailInfoGrid(
                    items: [
                      ('Montant', Formatters.money(amount)),
                      ('Client', tx.userName),
                      ('QR', tx.qrDisplayName),
                      (
                        'Date consommation',
                        DateFormat('dd-MM-yyyy HH:mm:ss').format(tx.date),
                      ),
                      ('État régularisation', tx.regularizationLabel),
                      (
                        'Réf régularisation',
                        tx.regularizationReference ?? '—',
                      ),
                      if (tx.regularizationDate != null)
                        (
                          'Date régularisation',
                          DateFormat(
                            'dd-MM-yyyy HH:mm',
                          ).format(tx.regularizationDate!),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Détail de la consommation',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...tx.lines.map((line) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            FaceValueChip(value: line.faceValue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${line.qty} ticket${line.qty > 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              Formatters.money(line.amount),
                              style: TextStyle(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _DetailFullWidthInfoCard extends StatelessWidget {
  const _DetailFullWidthInfoCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 12.2,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}


class _DetailInfoGrid extends StatelessWidget {
  const _DetailInfoGrid({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width - 16 * 2 - 10;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          SizedBox(
            width: width / 2,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 46, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 46,
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            "C'est tout pour le moment",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Aucune consommation enregistrée',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HistoryLoadingSkeleton extends StatelessWidget {
  const _HistoryLoadingSkeleton({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse = 0.35 + (animation.value * 0.35);
        return Column(
          children: [
            for (var i = 0; i < 5; i++) ...[
              _HistorySkeletonRow(opacity: pulse),
              if (i != 4)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE9ECEF),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _HistorySkeletonRow extends StatelessWidget {
  const _HistorySkeletonRow({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 4, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(widthFactor: 0.52, height: 15, opacity: opacity),
                const SizedBox(height: 7),
                _SkeletonBlock(widthFactor: 0.34, height: 11, opacity: opacity),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SkeletonBlock(widthFactor: 0.26, height: 13, opacity: opacity),
              const SizedBox(height: 5),
              _SkeletonBlock(widthFactor: 0.18, height: 10, opacity: opacity),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.widthFactor,
    required this.height,
    required this.opacity,
  });

  final double widthFactor;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * widthFactor;
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFDDE3E8),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
