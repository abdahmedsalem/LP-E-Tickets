import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/acpec_admin_report_summary.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import 'admin_shell_scaffold.dart';
import '../../auth/bloc/auth_bloc.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  AcpecAdminReportSummary? _summary;
  bool _acpecLoading = false;
  String? _acpecError;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcpecSummary());
    }
  }

  String _briefError(Object e) {
    if (ErrorPresenter.isBackendUnavailable(e)) {
      return ErrorPresenter.backendUnavailable();
    }
    return ErrorPresenter.message(e);
  }

  Future<void> _loadAcpecSummary() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    setState(() {
      _acpecLoading = true;
      _acpecError = null;
    });
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) throw Exception('Session requise.');
      final raw = await OdooFueltokenFacade().adminReportsSummary(const {});
      final s = AcpecAdminReportSummary.fromRpc(raw);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _acpecLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecError = _briefError(e);
        _acpecLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Rapports')),
        body: _buildAcpecBody(),
        bottomNavigationBar: AdminBottomTabsBar(
          selectedIndex: 2,
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/admin');
                return;
              case 1:
                context.go('/admin/achats');
                return;
              case 2:
                context.go('/admin/profile');
                return;
            }
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Rapports')),
      body: const ApiRequiredView(),
      bottomNavigationBar: AdminBottomTabsBar(
        selectedIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/admin');
              return;
            case 1:
              context.go('/admin/achats');
              return;
            case 2:
              context.go('/admin/profile');
              return;
          }
        },
      ),
    );
  }

  Widget _buildAcpecBody() {
    if (_acpecLoading && _summary == null) {
      return const Center(child: AppLoadingLottie(size: 100));
    }
    if (_acpecError != null && _summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppColors.danger.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 16),
              Text(
                _acpecError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadAcpecSummary,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final s = _summary;
    if (s == null) {
      return const Center(child: Text('Aucune donnée.'));
    }

    return RefreshIndicator(
      onRefresh: _loadAcpecSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_acpecError != null) ...[
            BackendUnavailableBanner(
              message: _acpecError!,
              onRetry: _loadAcpecSummary,
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insights_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vue globale',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${Formatters.numberFr(s.transactions)} transactions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InfoBanner(),
          const SizedBox(height: 20),
          _SectionHeader('Achats', Icons.shopping_cart_outlined),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'En attente',
                  value: s.purchasesSubmitted,
                  color: AppColors.warning,
                  icon: Icons.pending_actions_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  label: 'Validés',
                  value: s.purchasesApproved,
                  color: AppColors.success,
                  icon: Icons.verified_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader('QR codes', Icons.qr_code_2_outlined),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Actifs',
                  value: s.qrActive,
                  color: AppColors.primary,
                  icon: Icons.qr_code_scanner_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Bloqués',
                  value: s.qrBlocked,
                  color: AppColors.danger,
                  icon: Icons.block_flipped,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Consommés',
                  value: s.qrConsumed,
                  color: AppColors.accent,
                  icon: Icons.done_all_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Expirés',
                  value: s.qrExpired,
                  color: AppColors.muted,
                  icon: Icons.timer_off_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader('Portefeuilles & stations', Icons.hub_outlined),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Portefeuilles',
                  value: s.wallets,
                  color: AppColors.primaryDark,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  label: 'Stations actives',
                  value: s.stationsActive,
                  color: AppColors.success,
                  icon: Icons.local_gas_station_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader('Transactions', Icons.receipt_long_outlined),
          const SizedBox(height: 10),
          _MetricTile(
            label: 'Total transactions',
            value: s.transactions,
            color: AppColors.ink,
            icon: Icons.swap_horiz_rounded,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.infoSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.primaryDark.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Compteurs globaux synchronisés avec le serveur ACPEC.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.icon);

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 22,
          color: AppColors.primaryDark.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.softShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Formatters.number(value),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.05,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}
