import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
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
  static const Color _cOrange = Color(0xFF16A34A);
  static const Color _cDanger = Color(0xFFDC2626);

  List<BusinessTransaction> _items = [];
  bool _loading = true;
  String? _error;
  late final VoidCallback _walletBusListener;

  late DateTime _draftFrom;
  late DateTime _draftTo;
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
    _draftFrom = DateTime(now.year, now.month, now.day);
    _draftTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _activeFrom = _draftFrom;
    _activeTo = _draftTo;
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
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirÃ©e. Reconnectez-vous.';
    }
    return e.toString().replaceFirst('Exception: ', '').trim();
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
        _items = [];
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _filteredItems;
    final shown = items;

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
                  'Historique des consommations',
                  style: GoogleFonts.inter(
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
                  'Vos dernières consommations apparaîtront ici',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _cSecondaryText,
                    fontWeight: FontWeight.w500,
                  ),
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
              const SizedBox(height: 20),
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
    return Semantics(
      label: '${Formatters.numberFr(amount)} MRU',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
            TextSpan(text: ' MRU', style: unitStyle),
          ],
        ),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    final tx = widget.transaction;
    final amount = tx.totalAmount.abs();
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
                                color: _StationConsumptionHistoryScreenState
                                    ._cPrimaryText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$dateLabel $hourLabel',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _StationConsumptionHistoryScreenState
                                    ._cSecondaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _AmountInline(
                        amount: amount,
                        textAlign: TextAlign.right,
                        valueStyle: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _StationConsumptionHistoryScreenState._cDanger,
                          height: 1,
                          letterSpacing: -0.2,
                        ),
                        unitStyle: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _StationConsumptionHistoryScreenState._cDanger
                              .withValues(alpha: 0.82),
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: _StationHistoryDetailBody(
                  transaction: tx,
                  amount: amount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationHistoryDetailBody extends StatelessWidget {
  const _StationHistoryDetailBody({
    required this.transaction,
    required this.amount,
  });

  final BusinessTransaction transaction;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConsumptionDetailSummary(
          amount: amount,
          clientName: transaction.userName,
          stationName: transaction.stationName ?? 'Station inconnue',
          txType: transaction.type.label,
        ),
        if (transaction.lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...transaction.lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                      '${Formatters.numberFr(line.amount)} MRU',
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
        ],
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
                  style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'MRU',
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
                          'Consommation station',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
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
                    stationName: tx.stationName ?? 'Station inconnue',
                    txType: tx.type.label,
                  ),
                  const SizedBox(height: 14),
                  _DetailInfoGrid(
                    items: [
                      ('Transaction', tx.id),
                      ('Client ID', tx.userId),
                      ('Station ID', tx.stationId ?? 'â€”'),
                      ('QR', tx.qrId ?? tx.qrPublicCode ?? 'â€”'),
                      ('Lot ID', tx.lotId ?? 'â€”'),
                      ('RÃ©f lot', tx.lotInternalRef ?? 'â€”'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'DÃ©tail de la consommation',
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
                              '${Formatters.numberFr(line.amount)} MRU',
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
            label: const Text('RÃ©essayer'),
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
            'Aucune consommation enregistrÃ©e',
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
