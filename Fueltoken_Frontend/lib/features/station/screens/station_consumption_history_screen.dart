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
import '../../../shared/widgets/app_card.dart';
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
                  style: GoogleFonts.poppins(
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
                  style: GoogleFonts.poppins(
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
      label: Formatters.money(amount),
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

class _StationHistoryRow extends StatelessWidget {
  const _StationHistoryRow({required this.transaction});

  final BusinessTransaction transaction;

  Future<void> _openDetails(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final amount = transaction.totalAmount.abs();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.42,
          maxChildSize: 0.94,
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
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Consommation station',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Fermer',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
                      children: [
                        _StationConsumptionOverviewCard(
                          transaction: transaction,
                          amount: amount,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Détail de la consommation',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StationConsumptionDetailGrid(transaction: transaction),
                        if (transaction.lines.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            'Lignes de consommation',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
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
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
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
                                      style: GoogleFonts.poppins(
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
    final tx = transaction;
    final amount = tx.totalAmount.abs();
    final dateLabel = DateFormat('dd-MM-yyyy').format(tx.date);
    final hourLabel = DateFormat('HH:mm:ss').format(tx.date);
    final qrCode = (tx.qrPublicCode ?? tx.qrId ?? '—').trim();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      onTap: () => _openDetails(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_gas_station_rounded,
              size: 22,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${tx.stationName ?? 'Station inconnue'} • ${tx.userName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
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
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AmountInline(
                amount: amount,
                textAlign: TextAlign.right,
                valueStyle: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                  height: 1,
                  letterSpacing: -0.2,
                ),
                unitStyle: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger.withValues(alpha: 0.82),
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 96),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  qrCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StationConsumptionOverviewCard extends StatelessWidget {
  const _StationConsumptionOverviewCard({
    required this.transaction,
    required this.amount,
  });

  final BusinessTransaction transaction;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qrCode = (transaction.qrPublicCode ?? transaction.qrId ?? '—').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  transaction.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  transaction.stationName ?? 'Station inconnue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd-MM-yyyy HH:mm').format(transaction.date),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Montant',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '-${Formatters.number(amount)} ${Formatters.defaultCurrency}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                    height: 1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    qrCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationConsumptionDetailGrid extends StatelessWidget {
  const _StationConsumptionDetailGrid({required this.transaction});

  final BusinessTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final qrCode = (transaction.qrPublicCode ?? transaction.qrId ?? '—').trim();
    return _DetailInfoGrid(
      items: [
        ('QR code consommé', qrCode.isEmpty ? '—' : qrCode),
        ('Client concerné', transaction.userName),
        ('Station', transaction.stationName ?? 'Station inconnue'),
        ('Transaction', transaction.id),
      ],
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
    final qrRef = transaction.qrPublicCode ?? transaction.qrId;

    final rows = [
      if (transaction.userName.isNotEmpty)
        _StationTxDetailRow(label: 'Client concerné', value: transaction.userName),
      if (qrRef != null && qrRef.isNotEmpty)
        _StationTxDetailRow(label: 'QR code consommé', value: qrRef),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _StationTxDetailRowWidget(row: rows[i]),
          if (i < rows.length - 1)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8EAED)),
        ],
        if (transaction.lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Lignes',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.muted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < transaction.lines.length; i++) ...[
            _StationTxLineRow(line: transaction.lines[i]),
            if (i < transaction.lines.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _StationTxDetailRow {
  const _StationTxDetailRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _StationTxDetailRowWidget extends StatelessWidget {
  const _StationTxDetailRowWidget({required this.row});

  final _StationTxDetailRow row;

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
              style: GoogleFonts.poppins(
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
              style: GoogleFonts.poppins(
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

class _StationTxLineRow extends StatelessWidget {
  const _StationTxLineRow({required this.line});

  final TransactionLine line;

  String _qrTitle() {
    final qty = line.qty > 0 ? line.qty : 1;
    final ticketLabel =
        '${Formatters.numberFr(qty)} ticket${qty > 1 ? 's' : ''}';
    final carnetLabel = line.carnetSize > 0 && line.faceValue > 0
        ? 'carnet ${Formatters.numberFr(line.carnetSize)} x ${line.faceValue}'
        : line.carnetTypeName.trim().isNotEmpty
        ? line.carnetTypeName.trim().replaceFirst('Carnet', 'carnet')
        : line.faceValue > 0
        ? 'carnet ${Formatters.numberFr(line.faceValue)}'
        : 'carnet';
    return '$ticketLabel de $carnetLabel';
  }

  String? _subtitle() {
    if (line.expirationDate == null) return null;
    return 'Date d\'expiration : ${DateFormat('dd-MM-yyyy').format(line.expirationDate!)}';
  }

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AmountInline(
            amount: line.amount,
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.poppins(
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
                  style: GoogleFonts.poppins(
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
                style: GoogleFonts.poppins(
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
                          'Consommation station',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
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
                              Formatters.money(line.amount),
                              style: GoogleFonts.poppins(
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
