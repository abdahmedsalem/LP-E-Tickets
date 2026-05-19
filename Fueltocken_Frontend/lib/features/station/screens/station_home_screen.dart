import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../auth/bloc/auth_bloc.dart';

class StationHomeScreen extends StatefulWidget {
  const StationHomeScreen({super.key});

  @override
  State<StationHomeScreen> createState() => _StationHomeScreenState();
}

class _StationHomeScreenState extends State<StationHomeScreen> {
  List<BusinessTransaction> _consumptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard());
    } else {
      _loading = false;
    }
  }

  Future<void> _loadDashboard() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() {
      _loading = true;
    });
    try {
      final raw = await OdooFueltokenFacade().stationTransactions({
        'limit': 80,
        'offset': 0,
      });
      final page = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: 80,
        requestedOffset: 0,
      );
      final list =
          page.items.where((t) => t.type == TxType.stationConsumption).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _consumptions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consumptions = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    final scheme = Theme.of(context).colorScheme;
    final pageBg = const Color(0xFFF2F5F4);

    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(backgroundColor: pageBg, body: const ApiRequiredView());
    }

    final today = DateTime.now();
    final todays = _consumptions.where((t) {
      final d = t.date;
      return d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    }).toList();
    final todayCount = todays.length;
    final todayVolume = todays.fold<int>(0, (s, t) => s + t.totalAmount.abs());
    final todayClients = todays.map((t) => t.userId).toSet().length;
    final todayAverage = todayCount == 0
        ? 0
        : (todayVolume / todayCount).round();
    final recent = _consumptions.take(8).toList();

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      'Tableau de bord',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 29,
                          color: scheme.onSurface,
                        ),
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.38,
                  children: [
                    _StatCard(
                      label: 'QR scannés',
                      value: _loading ? '—' : '$todayCount',
                      icon: Icons.qr_code_scanner_rounded,
                      iconBg: const Color(0xFFE8F8EE),
                      iconColor: const Color(0xFF16A34A),
                    ),
                    _StatCard(
                      label: 'Volume',
                      value: _loading ? '—' : Formatters.numberFr(todayVolume),
                      suffix: 'MRU',
                      icon: Icons.payments_outlined,
                      iconBg: const Color(0xFFF9F0DA),
                      iconColor: const Color(0xFFA16207),
                    ),
                    _StatCard(
                      label: 'Clients uniques',
                      value: _loading ? '—' : '$todayClients',
                      icon: Icons.groups_rounded,
                      iconBg: const Color(0xFFE8F8EE),
                      iconColor: const Color(0xFF16A34A),
                    ),
                    _StatCard(
                      label: 'Ticket moyen',
                      value: _loading ? '—' : Formatters.numberFr(todayAverage),
                      suffix: 'MRU',
                      icon: Icons.receipt_long_outlined,
                      iconBg: const Color(0xFFE8F8EE),
                      iconColor: const Color(0xFF16A34A),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(34),
                      topRight: Radius.circular(34),
                    ),
                    border: Border.all(color: const Color(0xFFE6E9ED)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Consommations récentes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.close_rounded,
                              color: scheme.onSurfaceVariant,
                              size: 34,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: _loading && recent.isEmpty
                              ? const Center(child: AppLoadingLottie(size: 70))
                              : recent.isEmpty
                              ? const _EmptyConsumption()
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: recent.length,
                                  itemBuilder: (context, i) =>
                                      _ConsumptionRow(tx: recent[i]),
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Color(0xFFE9ECEF),
                                  ),
                                ),
                        ),
                      ],
                    ),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.suffix,
  });
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    height: 1.0,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      suffix!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsumptionRow extends StatelessWidget {
  const _ConsumptionRow({required this.tx});
  final BusinessTransaction tx;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('dd-MM-yyyy').format(tx.date);
    final hour = DateFormat('HH:mm').format(tx.date);
    final amount = tx.totalAmount.abs();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.userName,
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
                  '$date • $hour',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
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
                  color: const Color(0xFFDC2626),
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

class _EmptyConsumption extends StatelessWidget {
  const _EmptyConsumption();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history, color: scheme.primary, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune consommation enregistrée',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scannez votre premier QR pour commencer.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
