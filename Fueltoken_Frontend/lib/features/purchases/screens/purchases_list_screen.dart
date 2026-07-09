import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/notifications/purchase_validation_notification_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/purchases_refresh_bus.dart';
import '../../../data/models/purchase_lot.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Liste des achats (donnÃ©es locales ou synchronisÃ©es ACPEC selon la configuration).
class PurchasesListScreen extends StatefulWidget {
  const PurchasesListScreen({super.key});

  @override
  State<PurchasesListScreen> createState() => _PurchasesListScreenState();
}

class _PurchasesListScreenState extends State<PurchasesListScreen> {
  List<PurchaseLot> _lots = [];
  bool _loading = false;
  String? _error;

  late final VoidCallback _purchasesBusListener;

  @override
  void initState() {
    super.initState();
    _purchasesBusListener = () {
      if (mounted) _refresh();
    };
    PurchasesRefreshBus.instance.revision.addListener(_purchasesBusListener);
    _refresh();
  }

  @override
  void dispose() {
    PurchasesRefreshBus.instance.revision.removeListener(_purchasesBusListener);
    super.dispose();
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
        final raw = await OdooFueltokenFacade().purchasesList(
          const <String, dynamic>{},
        );
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
        try {
          await PurchaseValidationNotificationService.instance.syncForUser(
            user,
          );
        } catch (_) {}
      } on OdooJsonRpcException catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.isOdooSessionExpired
              ? 'Session expirÃ©e. Reconnectez-vous pour actualiser la liste.'
              : ErrorPresenter.message(e);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = ErrorPresenter.isBackendUnavailable(e)
              ? ErrorPresenter.backendUnavailable()
              : ErrorPresenter.message(e);
        });
      }
      return;
    }

    setState(() {
      _loading = false;
      _error = 'Connexion serveur ACPEC requise pour afficher vos achats.';
      _lots = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minEmptyHeight = math.max(
      320.0,
      MediaQuery.sizeOf(context).height - 200,
    );
    final totalLots = _lots.length;
    final approvedLots = _lots
        .where((lot) => lot.state == PurchaseLotState.approved)
        .length;
    final rejectedLots = _lots
        .where((lot) => lot.state == PurchaseLotState.rejected)
        .length;
    final totalAmount = _lots.fold<int>(0, (sum, lot) => sum + lot.totalAmount);

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/purchases/new');
          await _refresh();
        },
        backgroundColor: const Color(0xFF0F7A5A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvel achat'),
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FBFA), Color(0xFFF2F5F3), Color(0xFFF4F7F5)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Mes achats',
                subtitle:
                    'Chaque carte rÃ©sume le carnet, le montant total et la date de validation.',
                onBack: () => context.pop(),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$totalLots achats',
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryPill(
                        label: 'ValidÃ©s',
                        value: '$approvedLots',
                        color: const Color(0xFFDCFCE7),
                        foreground: const Color(0xFF0F7A5A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryPill(
                        label: 'RejetÃ©s',
                        value: '$rejectedLots',
                        color: const Color(0xFFFFE4E6),
                        foreground: const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryPill(
                        label: 'Montant',
                        value: Formatters.money(totalAmount),
                        color: const Color(0xFFF3F4F6),
                        foreground: const Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: const [
                          SizedBox(height: 18),
                          AppLoadingSkeleton(
                            style: AppLoadingSkeletonStyle.qrCards,
                            itemCount: 4,
                          ),
                        ],
                      )
                    : _error != null && _lots.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          SizedBox(
                            height: minEmptyHeight,
                            child: _EmptyPanel(
                              icon: Icons.cloud_off_outlined,
                              title: 'Connexion requise',
                              message: _error!,
                              actionLabel: 'RÃ©essayer',
                              onAction: _refresh,
                            ),
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        color: scheme.primary,
                        onRefresh: _refresh,
                        child: _lots.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  96,
                                ),
                                children: [
                                  SizedBox(
                                    height: minEmptyHeight,
                                    child: _EmptyPanel(
                                      icon: Icons.receipt_long_outlined,
                                      title: 'Aucun achat',
                                      message:
                                          'CrÃ©ez un nouvel achat pour faire apparaÃ®tre ici le carnet, le montant et sa validation.',
                                      actionLabel: 'Nouvel achat',
                                      onAction: () async {
                                        await context.push('/purchases/new');
                                        await _refresh();
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  96,
                                ),
                                itemCount:
                                    _lots.length + (_error != null ? 1 : 0),
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 14),
                                itemBuilder: (ctx, i) {
                                  if (_error != null && i == 0) {
                                    return BackendUnavailableBanner(
                                      message: _error!,
                                      onRetry: () {
                                        _refresh();
                                      },
                                    );
                                  }
                                  final lot = _lots[_error != null ? i - 1 : i];
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
    final stateColor = switch (lot.state) {
      PurchaseLotState.approved => const Color(0xFF0F7A5A),
      PurchaseLotState.submitted => const Color(0xFFB45309),
      PurchaseLotState.rejected => const Color(0xFFB91C1C),
      PurchaseLotState.draft => const Color(0xFF6B7280),
    };
    final amountColor = switch (lot.state) {
      PurchaseLotState.submitted => const Color(0xFF2563EB),
      PurchaseLotState.approved => const Color(0xFF0F7A5A),
      PurchaseLotState.rejected => const Color(0xFFB91C1C),
      PurchaseLotState.draft => const Color(0xFF6B7280),
    };
    final typeLabel = _purchaseTypeLabel(lot);
    final validationLabel = lot.validationDate != null
        ? Formatters.date(lot.validationDate!)
        : 'En attente de validation';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF8FAF9)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            stateColor.withValues(alpha: 0.16),
                            stateColor.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: stateColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  typeLabel,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: scheme.onSurface,
                                    height: 1.08,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                Formatters.money(lot.totalAmount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: amountColor,
                                  height: 1.08,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lot.internalRef,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              StatusBadge.lot(lot.state),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        title: 'Type de carnet',
                        value: typeLabel,
                        icon: Icons.style_outlined,
                        accent: stateColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricBlock(
                        title: 'Montant total',
                        value: Formatters.money(lot.totalAmount),
                        icon: Icons.payments_outlined,
                        accent: amountColor,
                        alignRight: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MetricBlock(
                  title: 'Date de validation',
                  value: validationLabel,
                  icon: Icons.event_available_outlined,
                  accent: stateColor,
                  fullWidth: true,
                ),
                if (lot.state == PurchaseLotState.rejected &&
                    lot.rejectionReason != null &&
                    lot.rejectionReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.report_gmailerrorred_outlined,
                          color: scheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lot.rejectionReason!,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
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

String _purchaseTypeLabel(PurchaseLot lot) {
  if (lot.lines.isEmpty) return 'Achat';
  final labels = lot.lines
      .map(
        (line) => Formatters.carnetTypeLabelFromServer(
          line.carnetTypeName,
          fallbackSize: line.carnetSize,
          fallbackFaceValue: line.faceValue,
        ).trim(),
      )
      .where((label) => label.isNotEmpty && label != 'Carnet')
      .toList();
  if (labels.isEmpty) return 'Carnet';
  if (labels.length == 1) return labels.first;
  return '${labels.first} +${labels.length - 1}';
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.fullWidth = false,
    this.alignRight = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final bool fullWidth;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EAE8)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: alignRight
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignRight ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    height: 1.15,
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

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
    required this.foreground,
  });

  final String label;
  final String value;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.88),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE5EAE7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF7EE), Color(0xFFDFF3EA)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: const Color(0xFF0F7A5A)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F7A5A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

