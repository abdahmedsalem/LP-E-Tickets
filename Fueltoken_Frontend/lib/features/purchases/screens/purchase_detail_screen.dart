import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_api_config.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/auth/payment_proof_http_headers.dart';
import '../../../core/utils/payment_proof.dart';
import '../../../data/services/payment_proof_loader.dart';
import '../../../data/models/purchase_lot.dart';
import '../../../data/models/user_role.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

class PurchaseDetailScreen extends StatefulWidget {
  final String lotId;
  final bool adminMode;

  const PurchaseDetailScreen({
    super.key,
    required this.lotId,
    this.adminMode = false,
  });

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseLot? _lot;
  bool _loading = false;
  bool _approving = false;
  bool _rejecting = false;
  bool _confirmingReject = false;
  final _rejectReasonController = TextEditingController();
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _rejectReasonController.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_confirmingReject) {
      _cancelRejectFlow();
      return;
    }
    if (widget.adminMode) {
      context.go('/admin');
      return;
    }
    context.pop();
  }

  Future<void> _refresh() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _lot = null;
        _loading = false;
        _loadError = 'Session requise.';
      });
      return;
    }

    if (AppEnvironment.useAcpecLiveData) {
      final purchaseId = _purchaseIdForRpc();
      if (purchaseId == null) {
        setState(() {
          _lot = null;
          _loading = false;
          _loadError =
              'Cette commande ne peut pas être ouverte. Vérifiez le lien ou réessayez.';
        });
        return;
      }

      setState(() {
        _loading = true;
        _loadError = null;
      });
      try {
        final params = <String, dynamic>{'purchase_id': purchaseId};
        final useAdminApi = widget.adminMode;
        final route = useAdminApi
            ? OdooFueltokenRpcConfig.adminPurchasesDetail
            : OdooFueltokenRpcConfig.purchasesDetail;
        AcpecFueltokenRpcCoordinator.shared.invalidate(route, params);

        final facade = OdooFueltokenFacade();
        final raw = useAdminApi
            ? await facade.adminPurchasesDetail(params)
            : await facade.purchasesDetail(params);
        var lot = AcpecPurchasesMapper.parsePurchaseDetail(
          raw,
          clientId: user.id,
          clientName: user.name,
          companyId: AppEnvironment.companyIdForUser(user),
          requestedPurchaseId: purchaseId,
        );
        if (lot.proofs.isEmpty) {
          if (useAdminApi) {
            try {
              final rawMobile = await facade.purchasesDetail(params);
              final mobileLot = AcpecPurchasesMapper.parsePurchaseDetail(
                rawMobile,
                clientId: user.id,
                clientName: user.name,
                companyId: AppEnvironment.companyIdForUser(user),
                requestedPurchaseId: purchaseId,
              );
              if (mobileLot.proofs.isNotEmpty) {
                lot = lot.copyWith(proofs: mobileLot.proofs);
              }
            } catch (_) {
              // Garde le détail admin sans preuves si le fallback mobile échoue.
            }
          }
          if (lot.proofs.isEmpty) {
            try {
              final rawList = await facade.purchasesList(
                const <String, dynamic>{},
              );
              final lots = AcpecPurchasesMapper.fromRpcResult(
                rawList,
                clientId: user.id,
                clientName: user.name,
                companyId: AppEnvironment.companyIdForUser(user),
              );
              final idStr = '$purchaseId';
              PurchaseLot? match;
              for (final l in lots) {
                if (l.id == idStr ||
                    AcpecPurchasesMapper.resolvePurchaseId(l.id) ==
                        purchaseId) {
                  match = l;
                  break;
                }
              }
              if (match != null && match.proofs.isNotEmpty) {
                lot = lot.copyWith(proofs: match.proofs);
              }
            } catch (_) {}
          }
        }
        lot = await _enrichProofsFromUrls(lot);
        if (!mounted) return;
        setState(() {
          _lot = lot;
          _loading = false;
        });
      } on OdooJsonRpcException catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = e.isOdooSessionExpired
              ? 'Session expirée. Reconnectez-vous.'
              : e.message;
          _lot = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = e.toString().replaceFirst('Exception: ', '');
          _lot = null;
        });
      }
      return;
    }

    setState(() {
      _loading = false;
      _loadError = 'Connexion serveur ACPEC requise pour afficher ce lot.';
      _lot = null;
    });
  }

  void _startRejectFlow() {
    setState(() {
      _confirmingReject = true;
    });
  }

  void _cancelRejectFlow() {
    setState(() {
      _confirmingReject = false;
      _rejectReasonController.clear();
    });
  }

  bool get _hideTechnicalRefs => false;

  /// Télécharge les pièces jointes Odoo (`/web/content/`) quand lAPI ne renvoie que lURL.
  Future<PurchaseLot> _enrichProofsFromUrls(PurchaseLot lot) async {
    if (lot.proofs.isEmpty) return lot;
    final enriched = <PurchaseProofSummary>[];
    var changed = false;
    for (final p in lot.proofs) {
      if (p.bytes != null && p.bytes!.isNotEmpty) {
        enriched.add(p);
        continue;
      }
      final url = p.url;
      if (url == null || url.isEmpty) {
        enriched.add(p);
        continue;
      }
      final bytes = await PaymentProofLoader.fetchBytes(url);
      if (bytes != null && bytes.isNotEmpty) {
        enriched.add(p.copyWith(bytes: bytes));
        changed = true;
      } else {
        enriched.add(p);
      }
    }
    if (!changed) return lot;
    return lot.copyWith(proofs: enriched);
  }

  /// Identifiant serveur pour les routes `purchase_id` (URL ou id issu du détail chargé).
  int? _purchaseIdForRpc() {
    final fromRoute = AcpecPurchasesMapper.resolvePurchaseId(widget.lotId);
    if (fromRoute != null) return fromRoute;
    final lot = _lot;
    if (lot != null) {
      return AcpecPurchasesMapper.resolvePurchaseId(lot.id);
    }
    return null;
  }

  String _briefPurchaseActionError(Object e) {
    if (e is OdooJsonRpcException) {
      if (e.isOdooSessionExpired || e.isAuthRequired) {
        return 'Session expirée. Reconnectez-vous.';
      }
      final m = e.message.trim();
      if (m.length > 160 ||
          m.contains('Traceback') ||
          m.contains('Exception(')) {
        return 'Lopération na pas abouti. Réessayez ou reconnectez-vous.';
      }
      return m;
    }
    return e.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _confirmApprove() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    if (AppEnvironment.useAcpecLiveData) {
      if (user.role != UserRole.admin && !widget.adminMode) return;
      final purchaseId = _purchaseIdForRpc();
      if (purchaseId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible deffectuer cette action pour cette commande.',
              ),
            ),
          );
        }
        return;
      }

      setState(() => _approving = true);
      try {
        final raw = await OdooFueltokenFacade().adminPurchasesApprove({
          'purchase_id': purchaseId,
        });
        AcpecPurchasesMapper.assertAdminActionOk(
          raw,
          fallback: 'Validation refusée.',
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.adminPurchasesPending,
          const {'state': 'all'},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.adminPurchasesDetail,
          {'purchase_id': purchaseId},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.purchasesList,
          const <String, dynamic>{},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.purchasesDetail,
          {'purchase_id': purchaseId},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.faces,
          const <String, dynamic>{},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.walletCurrent,
          Map<String, dynamic>.from(
            OdooFueltokenRpcConfig.walletCurrentDefaultParams,
          ),
        );
        WalletRefreshBus.instance.bump();
        await _refresh();
        if (!mounted) return;
        if (widget.adminMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Achat validé. Les tickets sont disponibles pour le client.',
              ),
            ),
          );
          context.pop(true);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lot validé. Les tickets sont disponibles pour le client.',
            ),
          ),
        );
      } on OdooJsonRpcException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_briefPurchaseActionError(e))));
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_briefPurchaseActionError(err))),
          );
        }
      } finally {
        if (mounted) setState(() => _approving = false);
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connexion serveur ACPEC requise pour valider ce lot.'),
        ),
      );
    }
  }

  Future<void> _confirmReject() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    final trimmed = _rejectReasonController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indiquez un motif de rejet avant de confirmer.'),
        ),
      );
      return;
    }

    if (AppEnvironment.useAcpecLiveData) {
      if (user.role != UserRole.admin && !widget.adminMode) return;
      final purchaseId = _purchaseIdForRpc();
      if (purchaseId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible deffectuer cette action pour cette commande.',
              ),
            ),
          );
        }
        return;
      }

      setState(() => _rejecting = true);
      try {
        final raw = await OdooFueltokenFacade().adminPurchasesReject({
          'purchase_id': purchaseId,
          'rejection_reason': trimmed,
        });
        AcpecPurchasesMapper.assertAdminActionOk(
          raw,
          fallback: 'Rejet refusé.',
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.adminPurchasesPending,
          const {'state': 'all'},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.adminPurchasesDetail,
          {'purchase_id': purchaseId},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.purchasesList,
          const <String, dynamic>{},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.purchasesDetail,
          {'purchase_id': purchaseId},
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.walletCurrent,
          Map<String, dynamic>.from(
            OdooFueltokenRpcConfig.walletCurrentDefaultParams,
          ),
        );
        WalletRefreshBus.instance.bump();
        await _refresh();
        if (!mounted) return;
        _cancelRejectFlow();
        if (widget.adminMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Achat rejeté. Le motif a été enregistré pour le client.',
              ),
            ),
          );
          context.pop(true);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lot rejeté. Le motif a été enregistré.'),
          ),
        );
      } on OdooJsonRpcException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_briefPurchaseActionError(e))));
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_briefPurchaseActionError(err))),
          );
        }
      } finally {
        if (mounted) setState(() => _rejecting = false);
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connexion serveur ACPEC requise pour rejeter ce lot.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = context.read<AuthBloc>().state.user;
    final isAdmin = user?.role == UserRole.admin;
    final showAdminBar =
        _lot != null &&
        (widget.adminMode || isAdmin == true) &&
        _lot!.state == PurchaseLotState.submitted;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: showAdminBar
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _confirmingReject
                    ? _RejectConfirmPanel(
                        lot: _lot!,
                        reasonController: _rejectReasonController,
                        busy: _rejecting,
                        onCancel: _cancelRejectFlow,
                        onConfirm: _confirmReject,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_approving || _rejecting)
                                  ? null
                                  : _startRejectFlow,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                minimumSize: const Size.fromHeight(48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: _rejecting
                                  ? const AppInlineLoading(size: 18)
                                  : const Icon(Icons.close_rounded),
                              label: Text(_rejecting ? 'Rejet' : 'Rejeter'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_approving || _rejecting)
                                  ? null
                                  : _confirmApprove,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.verified_rounded),
                              label: const Text('Valider lachat'),
                            ),
                          ),
                        ],
                      ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBarHeader(
              title: _confirmingReject ? 'Rejeter lachat' : 'Détail achat',
              onBack: _handleBack,
            ),
            Expanded(
              child: _loading
                  ? ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        AppLoadingSkeleton(
                          style: AppLoadingSkeletonStyle.qrCards,
                          itemCount: 1,
                        ),
                        SizedBox(height: 16),
                        AppLoadingSkeleton(
                          style: AppLoadingSkeletonStyle.historyRows,
                          itemCount: 5,
                        ),
                      ],
                    )
                  : _loadError != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: FilledButton.tonalIcon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          ),
                        ),
                      ],
                    )
                  : _lot == null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        SizedBox(height: 48),
                        Center(child: Text('Achat introuvable.')),
                      ],
                    )
                  : RefreshIndicator(
                      color: scheme.primary,
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        children: [
                          _PurchaseHeroCard(
                            lot: _lot!,
                            hideTechnicalRefs: _hideTechnicalRefs,
                          ),
                          if (widget.adminMode &&
                              _lot!.state == PurchaseLotState.submitted) ...[
                            const SizedBox(height: 16),
                            if (_confirmingReject)
                              const _AdminRejectStepsCard()
                            else
                              const _AdminValidationStepsCard(),
                          ],
                          if (_lot!.state == PurchaseLotState.rejected &&
                              _lot!.rejectionReason != null) ...[
                            const SizedBox(height: 14),
                            _RejectionCard(reason: _lot!.rejectionReason!),
                          ],
                          const SizedBox(height: 20),
                          const SectionLabel('Informations'),
                          _MetaCard(lot: _lot!),
                          const SizedBox(height: 20),
                          const SectionLabel('Lignes de commande'),
                          _LinesCard(lot: _lot!),
                          const SizedBox(height: 20),
                          const SectionLabel('Preuves de paiement'),
                          _ProofsSection(lot: _lot!),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseHeroCard extends StatelessWidget {
  const _PurchaseHeroCard({required this.lot, required this.hideTechnicalRefs});
  final PurchaseLot lot;
  final bool hideTechnicalRefs;

  AppPill _statusPill() {
    switch (lot.state) {
      case PurchaseLotState.approved:
        return AppPill(label: lot.state.label, tone: PillTone.green);
      case PurchaseLotState.rejected:
        return AppPill(label: lot.state.label, tone: PillTone.red);
      case PurchaseLotState.submitted:
        return AppPill(label: lot.state.label, tone: PillTone.amber);
      case PurchaseLotState.draft:
        return AppPill(label: lot.state.label, tone: PillTone.gray);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineSoft),
        boxShadow: AppColors.softShadow,
      ),
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
                  color: const Color(0xFFEAF7EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF2E7D32),
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
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lot.clientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.05,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _OverviewFact(
                icon: Icons.layers_outlined,
                label: '${Formatters.numberFr(lot.totalFaces)} tickets',
              ),
              const SizedBox(width: 12),
              _OverviewFact(
                icon: Icons.payments_outlined,
                label: Formatters.money(lot.totalAmount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.lot});
  final PurchaseLot lot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.flag_outlined,
            label: 'Statut',
            value: lot.state.label,
            trailing: Icon(
              lot.state == PurchaseLotState.approved
                  ? Icons.check_circle_outline_rounded
                  : lot.state == PurchaseLotState.rejected
                  ? Icons.cancel_outlined
                  : Icons.radio_button_unchecked_rounded,
              color: lot.state == PurchaseLotState.approved
                  ? AppColors.success
                  : lot.state == PurchaseLotState.rejected
                  ? AppColors.danger
                  : AppColors.muted,
              size: 22,
            ),
          ),
          _InfoRow(
            icon: Icons.person_outline,
            label: 'Client',
            value: lot.clientName,
          ),
          if (lot.paymentReference != null &&
              lot.paymentReference!.trim().isNotEmpty)
            _InfoRow(
              icon: Icons.tag_outlined,
              label: 'R?f?rence paiement',
              value: lot.paymentReference!.trim(),
            ),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'Soumis le',
            value: Formatters.dateTimeDash(lot.createdAt),
          ),
          _InfoRow(
            icon: Icons.event_outlined,
            label: 'Expiration des tickets',
            value: Formatters.dateTimeDash(lot.expirationDate),
          ),
          if (lot.validationDate != null)
            _InfoRow(
              icon: Icons.verified_outlined,
              label: 'Valid? le',
              value: Formatters.dateTimeDash(lot.validationDate!),
            ),
          if (lot.validatorName != null && lot.validatorName!.trim().isNotEmpty)
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Valid? par',
              value: lot.validatorName!.trim(),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppColors.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _RejectionCard extends StatelessWidget {
  const _RejectionCard({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSurface,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cancel_outlined,
                color: AppColors.danger,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motif de rejet',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.lot});
  final PurchaseLot lot;

  @override
  Widget build(BuildContext context) {
    if (lot.lines.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Text(
          AppEnvironment.useAcpecLiveData
              ? 'Le serveur n?a pas renvoy? de lignes pour cet achat. V?rifiez que la commande existe et vous appartient.'
              : 'Aucune ligne pour ce lot.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < lot.lines.length; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      Formatters.numberFr(lot.lines[i].faceValue),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lot.lines[i].carnetTypeCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${lot.lines[i].carnetCount} carnet${lot.lines[i].carnetCount > 1 ? 's' : ''} ? ${lot.lines[i].faceCount} tickets',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.money(lot.lines[i].lineAmount),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (i < lot.lines.length - 1)
              const Divider(height: 1, color: AppColors.lineSoft),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Total commande',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const Spacer(),
                Text(
                  Formatters.money(lot.totalAmount),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                    fontSize: 16,
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

class _ProofsSection extends StatelessWidget {
  const _ProofsSection({required this.lot});
  final PurchaseLot lot;

  @override
  Widget build(BuildContext context) {
    final items = lot.proofs.where((p) => p.isDisplayable).toList();
    final path = lot.paymentProofPath?.trim();
    final pathLooksLikeFile = looksLikeAttachmentFilename(path);

    if (items.isEmpty && (path == null || path.isEmpty || !pathLooksLikeFile)) {
      return const AppCard(
        padding: EdgeInsets.all(16),
        child: Text(
          'Aucune preuve de paiement jointe à cet achat.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      );
    }

    final displayItems = items.isNotEmpty
        ? items
        : [
            PurchaseProofSummary(
              label: 'Preuve de paiement',
              filename: path,
              url: path,
              mimeType: null,
              uploadedAt: null,
              bytes: null,
            ),
          ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          for (var i = 0; i < displayItems.length; i++) ...[
            _ProofTile(proof: displayItems[i]),
            if (i != displayItems.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ProofTile extends StatelessWidget {
  const _ProofTile({required this.proof});
  final PurchaseProofSummary proof;

  Future<Uint8List?> _resolveBytes() async {
    if (proof.bytes != null && proof.bytes!.isNotEmpty) return proof.bytes;
    final url = _resolvedProofUrl();
    if (url == null || url.isEmpty) return null;
    return PaymentProofLoader.fetchBytes(url);
  }

  String _safeFileName() {
    final raw = proof.filename?.trim();
    if (raw != null && raw.isNotEmpty && raw != 'false') return raw;
    final base = proof.label.trim().isEmpty ? 'preuve_paiement' : proof.label;
    return '${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')}.jpg';
  }

  String? _resolvedProofUrl() {
    final url = proof.url?.trim();
    if (url == null || url.isEmpty || url == 'false') return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = OdooApiConfig.baseUrlTrimmed;
    if (base.isEmpty) return url;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  Future<void> _downloadProof(BuildContext context) async {
    try {
      final bytes = await _resolveBytes();
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Téléchargement indisponible.')),
          );
        }
        return;
      }

      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}${_safeFileName()}',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preuve téléchargée: ${file.path}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de télécharger la preuve.')),
        );
      }
    }
  }

  Future<void> _openPreview(BuildContext context) async {
    final url = _resolvedProofUrl();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Preuve de paiement'),
              actions: [
                IconButton(
                  tooltip: 'Télécharger',
                  onPressed: () async {
                    await _downloadProof(ctx);
                  },
                  icon: const Icon(Icons.download_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 3,
                            child: _ProofImagePreview(
                              bytes: proof.bytes,
                              imageUrl: proof.bytes == null ? url : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Fermer'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await _downloadProof(ctx);
                            },
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Télécharger'),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                            ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = proof.url?.trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1.55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => _openPreview(context),
                  child: Container(color: AppColors.surfaceAlt),
                ),
                GestureDetector(
                  onTap: () => _openPreview(context),
                  child: _ProofImagePreview(
                    bytes: proof.bytes,
                    imageUrl: proof.bytes == null ? _resolvedProofUrl() : null,
                  ),
                ),
                if (url != null && url.isNotEmpty)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openPreview(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.lineSoft),
                            ),
                            child: Text(
                              'Ouvrir',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _downloadProof(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.download_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Télécharger',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProofImagePreview extends StatefulWidget {
  const _ProofImagePreview({this.bytes, this.imageUrl});

  final Uint8List? bytes;
  final String? imageUrl;

  @override
  State<_ProofImagePreview> createState() => _ProofImagePreviewState();
}

class _ProofImagePreviewState extends State<_ProofImagePreview> {
  Uint8List? _loaded;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loaded = widget.bytes;
    if ((_loaded == null || _loaded!.isEmpty) &&
        widget.imageUrl != null &&
        widget.imageUrl!.isNotEmpty) {
      _fetchRemote();
    }
  }

  @override
  void didUpdateWidget(covariant _ProofImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bytes != null &&
        widget.bytes!.isNotEmpty &&
        widget.bytes != oldWidget.bytes) {
      setState(() => _loaded = widget.bytes);
      return;
    }
    if (oldWidget.imageUrl != widget.imageUrl &&
        (_loaded == null || _loaded!.isEmpty)) {
      _fetchRemote();
    }
  }

  Future<void> _fetchRemote() async {
    if (_loading) return;
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _loading = true);
    final bytes = await PaymentProofLoader.fetchBytes(url);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (bytes != null && bytes.isNotEmpty) _loaded = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _loaded;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _broken(),
      );
    }
    final url = PaymentProofLoader.resolveProofUrl(widget.imageUrl);
    if (url == null || url.isEmpty) {
      return _loading ? _spinner() : _broken();
    }
    return FutureBuilder<Map<String, String>>(
      future: paymentProofHttpHeaders(),
      builder: (context, snap) {
        if (_loading && (snap.connectionState != ConnectionState.done)) {
          return _spinner();
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          headers: snap.data ?? const {},
          errorBuilder: (_, _, _) => _broken(),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return _spinner();
          },
        );
      },
    );
  }

  Widget _spinner() => Container(
    color: AppColors.surfaceAlt,
    alignment: Alignment.center,
    child: const SizedBox(
      width: 160,
      child: AppLoadingSkeleton(
        style: AppLoadingSkeletonStyle.historyRows,
        itemCount: 1,
      ),
    ),
  );

  Widget _broken() => Container(
    color: AppColors.surfaceAlt,
    alignment: Alignment.center,
    child: const Icon(
      Icons.broken_image_outlined,
      color: AppColors.muted,
      size: 36,
    ),
  );
}

class _OverviewFact extends StatelessWidget {
  const _OverviewFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.body,
          ),
        ),
      ],
    );
  }
}

class _AdminValidationStepsCard extends StatelessWidget {
  const _AdminValidationStepsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avant de valider',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 12),
          _ValidationStep(
            index: 1,
            title: 'Contrôler les preuves',
            subtitle: 'Montant et documents de paiement.',
          ),
          _ValidationStep(
            index: 2,
            title: 'Valider ou rejeter',
            subtitle: 'Le client verra le résultat sur sa commande.',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ValidationStep extends StatelessWidget {
  const _ValidationStep({
    required this.index,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
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

class _AdminRejectStepsCard extends StatelessWidget {
  const _AdminRejectStepsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rejet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 12),
          _ValidationStep(
            index: 1,
            title: 'Motif visible client',
            subtitle: 'Formulez une raison claire et factuelle.',
          ),
          _ValidationStep(
            index: 2,
            title: 'Aucun ticket généré',
            subtitle: 'Le client pourra corriger et renvoyer une commande.',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _RejectConfirmPanel extends StatelessWidget {
  const _RejectConfirmPanel({
    required this.lot,
    required this.reasonController,
    required this.busy,
    required this.onCancel,
    required this.onConfirm,
  });

  final PurchaseLot lot;
  final TextEditingController reasonController;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  static const _suggestedReasons = [
    'Preuve non conforme.',
    'Montant incohérent avec la commande.',
    'Référence de paiement invalide.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.block_rounded,
                    size: 20,
                    color: AppColors.danger.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Confirmer le rejet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rejeter ce lot pour ${lot.clientName}. '
                'Le lot sera marqué rejeté avec le motif saisi.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                enabled: !busy,
                autofocus: true,
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Motif de rejet',
                  hintText: 'Ex. Preuve non conforme.',
                  filled: true,
                  fillColor: Colors.white,
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hint in _suggestedReasons)
                    ActionChip(
                      label: Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () {
                              reasonController.text = hint;
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                icon: busy
                    ? AppInlineLoading(size: 22)
                    : const Icon(Icons.close_rounded),
                label: Text(busy ? 'Rejet' : 'Confirmer le rejet'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
