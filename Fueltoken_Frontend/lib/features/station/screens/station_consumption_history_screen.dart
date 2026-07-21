import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/date_range_filter_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../auth/bloc/auth_bloc.dart';

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
  static const Color _cPrimaryText = Color(0xFF111827);
  static const Color _cSecondaryText = Color(0xFF4B5563);

  List<BusinessTransaction> _items = [];
  bool _loading = true;
  String? _error;
  late final VoidCallback _walletBusListener;

  late DateTime _activeFrom;
  late DateTime _activeTo;
  late final AnimationController _skeletonCtrl;

  @override
  void initState() {
    super.initState();
    _skeletonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    final now = DateTime.now();
    _activeFrom = DateTime(now.year, now.month, now.day);
    _activeTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    // Recharger l'historique quand un scan est effectuÃ© (WalletRefreshBus)
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
    final l10n = AppLocalizations.of(context);
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return l10n.stationSessionExpired;
    }
    if (ErrorPresenter.isBackendUnavailable(e)) {
      return l10n.commonServerUnavailable;
    }
    return ErrorPresenter.localizedMessage(context, e);
  }

  Future<void> _load() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).commonSessionRequired;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await OdooFueltokenFacade().stationTransactions({
        'limit': _pageSize,
        'offset': 0,
      });
      final page = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: _pageSize,
        requestedOffset: 0,
      );
      final list =
          page.items.where((t) => t.type == TxType.stationConsumption).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _items = list;
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

  List<BusinessTransaction> get _filteredItems {
    return _items.where((tx) {
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

  void _applyFilter(DateTimeRange range) {
    setState(() {
      _activeFrom = range.start;
      _activeTo = range.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final items = _filteredItems;
    final shown = items;
    final totalAmount = shown.fold<int>(
      0,
      (sum, transaction) => sum + transaction.totalAmount.abs(),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _HeaderIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.go('/station/home'),
                    ),
                    const Spacer(),
                    _HeaderIconButton(
                      icon: Icons.filter_list_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.stationConsumptionHistory,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _cPrimaryText,
                    height: 1.08,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.stationHistorySubtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _cSecondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DateRangeFilterBar(
                  initialFrom: _activeFrom,
                  initialTo: _activeTo,
                  onApply: _applyFilter,
                ),
              ),
              const SizedBox(height: 14),
              if (!_loading && shown.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _StationHistoryTotalsCard(
                    totalAmount: totalAmount,
                    qrCount: shown.length,
                    periodLabel:
                        '${DateFormat('dd-MM-yyyy').format(_activeFrom)} → '
                        '${DateFormat('dd-MM-yyyy').format(_activeTo)}',
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 6),
              if (_error != null && _items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: BackendUnavailableBanner(
                    message: _error!,
                    onRetry: _load,
                  ),
                ),
              if (_loading && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _HistoryLoadingSkeleton(animation: _skeletonCtrl),
                )
              else if (_error != null && _items.isEmpty)
                _ErrorPanel(message: _error!, onRetry: _load)
              else if (shown.isEmpty)
                EmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: l10n.stationHistoryEmptyTitle,
                  message: l10n.stationHistoryEmptyMessage,
                )
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
                        l10n.stationHistoryEndTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.stationHistoryEndMessage,
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
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: const Color(0xFF374151)),
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
    final l10n = AppLocalizations.of(context);
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
                      l10n.stationHistorySummary,
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
                  label: l10n.stationConsumedQr,
                  value: Formatters.number(qrCount),
                  icon: Icons.qr_code_2_rounded,
                  valueColor: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StationHistoryTotalTile(
                  label: l10n.stationTotal,
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
          SizedBox(
            width: double.infinity,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: valueColor,
                height: 1,
                letterSpacing: -0.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationHistoryRow extends StatefulWidget {
  const _StationHistoryRow({required this.transaction});

  final BusinessTransaction transaction;

  @override
  State<_StationHistoryRow> createState() => _StationHistoryRowState();
}

class _StationHistoryRowState extends State<_StationHistoryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final amount = tx.totalAmount.abs();
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.stationFuelConsumption,
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
                          Text(
                            Formatters.money(amount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                              height: 1,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '$dateLabel $hourLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 22,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        child: _StationConsumptionPanel(transaction: tx),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationConsumptionPanel extends StatelessWidget {
  const _StationConsumptionPanel({required this.transaction});

  final BusinessTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tx = transaction;
    final titleCode = tx.qrDisplayName;
    final clientLabel = tx.userName.trim().isEmpty
        ? l10n.stationUnknownClient
        : tx.userName.trim();
    final stationLabel = (tx.stationName ?? '').trim().isEmpty
        ? l10n.stationUnknownStation
        : tx.stationName!.trim();
    final rows = <({String label, String value})>[
      (label: l10n.stationTransactionNumber, value: tx.txNumber),
      (label: l10n.stationClient, value: clientLabel),
      (label: l10n.station, value: stationLabel),
      (label: l10n.stationQrCode, value: titleCode),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _StationInfoRow(label: rows[i].label, value: rows[i].value),
          if (i < rows.length - 1)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8EAED)),
        ],
      ],
    );
  }
}

class _StationInfoRow extends StatelessWidget {
  const _StationInfoRow({required this.label, required this.value});

  final String label;
  final String value;

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
              label,
              style: const TextStyle(
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
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
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
                style: const TextStyle(
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
    final l10n = AppLocalizations.of(context);
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
                          l10n.stationFuelConsumption,
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
                    stationName: tx.stationName ?? l10n.stationUnknownStation,
                    txType: l10n.stationFuelConsumption,
                  ),
                  const SizedBox(height: 14),
                  _DetailInfoGrid(
                    items: [
                      (l10n.stationTransactionIdentifier, tx.id),
                      (l10n.stationClientIdentifier, tx.userId),
                      (
                        l10n.stationStationIdentifier,
                        tx.stationId ?? l10n.commonNotProvided,
                      ),
                      (
                        l10n.stationQrIdentifier,
                        tx.qrId ?? tx.qrPublicCode ?? l10n.commonNotProvided,
                      ),
                      (
                        l10n.stationLotIdentifier,
                        tx.lotId ?? l10n.commonNotProvided,
                      ),
                      (
                        l10n.lotReference,
                        tx.lotInternalRef ?? l10n.commonNotProvided,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.stationConsumptionDetail,
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
                                l10n.ticketCount(line.qty),
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
                      fontSize: 10,
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
            label: Text(AppLocalizations.of(context).commonRetry),
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
