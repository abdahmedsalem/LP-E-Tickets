import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/purchase_lot.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Liste des achats (données locales ou synchronisées ACPEC selon la configuration).
class PurchasesListScreen extends StatefulWidget {
  const PurchasesListScreen({super.key});
  @override
  State<PurchasesListScreen> createState() => _PurchasesListScreenState();
}

class _PurchasesListScreenState extends State<PurchasesListScreen> {
  List<PurchaseLot> _lots = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _lots = [];
        _loading = false;
        _error = 'Session requise.';
      });
      return;
    }

    if (AppEnvironment.useAcpecLiveData) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final raw = await OdooFueltokenFacade()
            .purchasesList(const <String, dynamic>{});
        final lots = AcpecPurchasesMapper.fromRpcResult(
          raw,
          clientId: user.id,
          clientName: user.name,
          companyId: AppEnvironment.companyIdForUser(user),
        );
        if (!mounted) return;
        setState(() {
          _lots = lots;
          _loading = false;
        });
      } on OdooJsonRpcException catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.isOdooSessionExpired
              ? 'Session expirée. Reconnectez-vous pour actualiser la liste.'
              : e.message;
          _lots = [];
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
          _lots = [];
        });
      }
      return;
    }

    setState(() {
      _loading = false;
      _error =
          'Connexion serveur ACPEC requise pour afficher vos achats.';
      _lots = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minEmptyHeight =
        math.max(320.0, MediaQuery.sizeOf(context).height - 200);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/purchases/new');
          await _refresh();
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouvel achat'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBarHeader(
              title: 'Mes achats',
              subtitle: AppEnvironment.useAcpecLiveData
                  ? 'Vos commandes de carnets'
                  : 'Mode démonstration',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: AppLoadingLottie(size: 100))
                  : _error != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            SizedBox(
                              height: minEmptyHeight,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    size: 48,
                                    color: scheme.error,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton.tonalIcon(
                                    onPressed: _refresh,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Réessayer'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                          color: scheme.primary,
                          onRefresh: _refresh,
                          child: _lots.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  children: [
                                    SizedBox(
                                      height: minEmptyHeight,
                                      child: EmptyState(
                                        icon: Icons.receipt_long_outlined,
                                        title: 'Aucun achat',
                                        message:
                                            'Soumettez une commande de carnets '
                                            'avec preuve de paiement.',
                                        action: ElevatedButton.icon(
                                          onPressed: () async {
                                            await context
                                                .push('/purchases/new');
                                            await _refresh();
                                          },
                                          icon: const Icon(Icons.add),
                                          label: const Text('Nouvel achat'),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 96),
                                  itemCount: _lots.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (ctx, i) {
                                    final lot = _lots[i];
                                    return _PurchaseTile(
                                      lot: lot,
                                      onTap: () => context
                                          .push('/purchases/${lot.id}')
                                          .then((_) => _refresh()),
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.lot, required this.onTap});

  final PurchaseLot lot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPublic = lot.publicCode.trim().isNotEmpty;

    return Material(
      color: scheme.surface,
      elevation: 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: scheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lot.internalRef,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              height: 1.2,
                            ),
                          ),
                          if (hasPublic) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.tag_outlined,
                                  size: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    lot.publicCode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge.lot(lot.state),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${lot.totalFaces} tickets · '
                          '${Formatters.money(lot.totalAmount)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        Formatters.date(lot.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lot.state == PurchaseLotState.rejected &&
                    lot.rejectionReason != null &&
                    lot.rejectionReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lot.rejectionReason!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: scheme.error,
                              fontWeight: FontWeight.w500,
                            ),
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
      ),
    );
  }
}
