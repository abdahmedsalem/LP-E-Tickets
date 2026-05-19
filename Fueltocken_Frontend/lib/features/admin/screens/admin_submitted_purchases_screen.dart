import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/purchase_lot.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';

class AdminSubmittedPurchasesScreen extends StatefulWidget {
  const AdminSubmittedPurchasesScreen({super.key});

  @override
  State<AdminSubmittedPurchasesScreen> createState() =>
      _AdminSubmittedPurchasesScreenState();
}

class _AdminSubmittedPurchasesScreenState
    extends State<AdminSubmittedPurchasesScreen> {
  List<PurchaseLot>? _acpecLots;
  bool _acpecLoading = false;
  String? _acpecError;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcpecPending());
    }
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    return e.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _loadAcpecPending() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    setState(() {
      _acpecLoading = true;
      _acpecError = null;
    });
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) throw Exception('Session requise.');
      final companyId = AppEnvironment.companyIdForUser(user);
      final raw = await OdooFueltokenFacade().adminPurchasesPending({
        'state': 'submitted',
      });
      final lots = AcpecPurchasesMapper.fromRpcResult(
        raw,
        clientId: user.id,
        clientName: user.name,
        companyId: companyId,
      );
      if (!mounted) return;
      setState(() {
        _acpecLots = lots
            .where((lot) => lot.state == PurchaseLotState.submitted)
            .toList();
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

  List<PurchaseLot> _submittedLots() {
    return _acpecLots ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        automaticallyImplyLeading: false,
        title: Text(
          'Achats',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          if (AppEnvironment.useAcpecLiveData)
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _acpecLoading ? null : _loadAcpecPending,
              icon: _acpecLoading
                  ? const AppInlineLoading(size: 22)
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: AppEnvironment.useAcpecLiveData
          ? _buildAcpecBody()
          : const SizedBox.shrink(),
    );
  }

  Widget _buildAcpecBody() {
    if (_acpecLoading && (_acpecLots == null || _acpecLots!.isEmpty)) {
      return const AppPageLoading();
    }
    if (_acpecError != null && (_acpecLots == null || _acpecLots!.isEmpty)) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppErrorLottie(size: 120),
              const SizedBox(height: 16),
              Text(
                _acpecError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadAcpecPending,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.infoSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
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
                Expanded(
                  child: Text(
                    '${_submittedLots().length} achat(s) soumis',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAcpecPending,
            child: _LotsList(
              lots: _submittedLots(),
              onTap: (lot) async {
                final ok = await context.push<bool>(
                  '/admin/purchases/${lot.id}',
                );
                if (ok == true && mounted) await _loadAcpecPending();
              },
              useAcpecCards: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _LotsList extends StatelessWidget {
  final List<PurchaseLot> lots;
  final void Function(PurchaseLot) onTap;
  final bool useAcpecCards;

  const _LotsList({
    required this.lots,
    required this.onTap,
    this.useAcpecCards = false,
  });

  @override
  Widget build(BuildContext context) {
    if (lots.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.assignment_outlined,
            title: 'Aucun lot',
            message: 'Aucun lot ne correspond à ce filtre.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: lots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final lot = lots[i];
        if (useAcpecCards) {
          return _AcpecAdminLotCard(lot: lot, onTap: () => onTap(lot));
        }
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(lot),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lot.internalRef,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusBadge.lot(lot.state),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lot.clientName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${lot.totalFaces} faces',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        Formatters.money(lot.totalAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AcpecAdminLotCard extends StatelessWidget {
  const _AcpecAdminLotCard({required this.lot, required this.onTap});

  final PurchaseLot lot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stColor = switch (lot.state) {
      PurchaseLotState.submitted => AppColors.warning,
      PurchaseLotState.approved => AppColors.success,
      PurchaseLotState.rejected => AppColors.danger,
      _ => AppColors.muted,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
            boxShadow: AppColors.softShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        lot.clientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink,
                          height: 1.2,
                        ),
                      ),
                    ),
                    StatusBadge.lot(lot.state),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 17, color: stColor),
                    const SizedBox(width: 6),
                    Text(
                      Formatters.money(lot.totalAmount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppColors.muted.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      Formatters.dateTimeDash(lot.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
