import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/purchases_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/acpec_admin_report_summary.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../auth/bloc/auth_bloc.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  AcpecAdminReportSummary? _summary;
  String? _error;
  late final VoidCallback _refreshBusListener;

  @override
  void initState() {
    super.initState();
    _refreshBusListener = () {
      if (mounted && AppEnvironment.useAcpecLiveData) _loadSummary();
    };
    WalletRefreshBus.instance.revision.addListener(_refreshBusListener);
    PurchasesRefreshBus.instance.revision.addListener(_refreshBusListener);
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
    }
  }

  @override
  void dispose() {
    WalletRefreshBus.instance.revision.removeListener(_refreshBusListener);
    PurchasesRefreshBus.instance.revision.removeListener(_refreshBusListener);
    super.dispose();
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    return e.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _loadSummary() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    setState(() {
      _error = null;
    });
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) throw Exception('Session requise.');
      final raw = await OdooFueltokenFacade().adminReportsSummary(const {});
      final summary = AcpecAdminReportSummary.fromRpc(raw);
      if (!mounted) return;
      setState(() {
        _summary = summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _briefError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user!;
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? null
        : AppColors.softShadow;

    final pending = _summary?.purchasesSubmitted ?? 0;
    final approved = _summary?.purchasesApproved ?? 0;
    final consumed = _summary?.consumptionVolumeMru ?? 0;

    return Scaffold(
      backgroundColor: pageBg,
      body: RefreshIndicator(
        onRefresh: AppEnvironment.useAcpecLiveData ? _loadSummary : () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Administration',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -0.4,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null && AppEnvironment.useAcpecLiveData) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF39B54A),
                    const Color(0xFF67C66C).withValues(alpha: 0.96),
                    const Color(0xFF9B5DE5).withValues(alpha: 0.92),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF39B54A).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _HeaderStat(
                          label: 'En attente',
                          value: '$pending',
                          light: true,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      Expanded(
                        child: _HeaderStat(
                          label: 'Validés',
                          value: '$approved',
                          light: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _WideStatCard(
              label: 'Volume consommé (toutes stations)',
              value: Formatters.money(consumed),
              icon: Icons.local_gas_station_rounded,
              color: const Color(0xFFF4C542),
              scheme: scheme,
              shadow: shadow,
            ),
            const SizedBox(height: 16),
            Text(
              'ACTIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _ActionCard(
                        icon: Icons.assignment_turned_in_outlined,
                        title: 'Validation lot',
                        accent: const Color(0xFF33A853),
                        scheme: scheme,
                        shadow: shadow,
                        onTap: () => context.go('/admin/lots'),
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _ActionCard(
                        icon: Icons.local_gas_station_rounded,
                        title: 'Station',
                        accent: const Color(0xFF33A853),
                        scheme: scheme,
                        shadow: shadow,
                        onTap: () => context.go('/admin/stations'),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: _ActionCard(
                        icon: Icons.bar_chart_rounded,
                        title: 'Rapports',
                        accent: const Color(0xFF1F9D49),
                        scheme: scheme,
                        shadow: shadow,
                        wide: true,
                        compact: true,
                        onTap: () => context.go('/admin/reports'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    required this.light,
  });

  final String label;
  final String value;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: light ? Colors.white : AppColors.ink,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: light
                ? Colors.white.withValues(alpha: 0.85)
                : AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _WideStatCard extends StatelessWidget {
  const _WideStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.scheme,
    this.shadow,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ColorScheme scheme;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
        boxShadow: shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    letterSpacing: -0.3,
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.scheme,
    this.shadow,
    this.wide = false,
    this.compact = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final ColorScheme scheme;
  final List<BoxShadow>? shadow;
  final bool wide;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isReport = title.toLowerCase().contains('rapport');
    if (!isReport) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          final circleDiameter = math.min(
            54.0,
            math.max(46.0, cardWidth * 0.42),
          );
          final iconSize = circleDiameter * 0.42;
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            elevation: 0,
            shadowColor: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.line.withValues(alpha: 0.9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.055),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(10.0, cardWidth * 0.07),
                    vertical: math.max(12.0, cardWidth * 0.085),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: circleDiameter,
                        height: circleDiameter,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          color: AppColors.leaderGreen,
                          size: iconSize,
                        ),
                      ),
                      SizedBox(height: math.max(10.0, cardWidth * 0.08)),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: math.min(
                            14.5,
                            math.max(12.5, cardWidth * 0.13),
                          ),
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                          color: AppColors.ink,
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

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 7),
                spreadRadius: -6,
              ),
            ],
          ),
          child: SizedBox(
            height: wide ? (compact ? 72 : 96) : 128,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: wide ? (compact ? 10 : 12) : 12,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: wide ? (compact ? 34 : 42) : 46,
                      height: wide ? (compact ? 34 : 42) : 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: wide ? (compact ? 17 : 22) : 24,
                      ),
                    ),
                    SizedBox(height: wide ? (compact ? 4 : 10) : 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: wide ? (compact ? 12 : 14) : 13,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
