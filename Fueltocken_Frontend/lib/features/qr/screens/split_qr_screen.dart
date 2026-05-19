import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/acpec_qr_split_builder.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Répartition des tickets du QR parent vers plusieurs **parties** (nouveaux QR) —
/// `POST …/mobile/qr/split` (doctrine FuelToken § I, § 5.12).
class SplitQrScreen extends StatefulWidget {
  final String qrId;
  const SplitQrScreen({super.key, required this.qrId});

  @override
  State<SplitQrScreen> createState() => _SplitQrScreenState();
}

class _SplitQrScreenState extends State<SplitQrScreen> {
  QrToken? _parent;
  /// Par partie : `lineId` parent → quantité de tickets affectés.
  List<Map<String, int>> _partitions = [{}, {}];
  bool _submitting = false;
  bool _loadingParent = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadParent());
    } else {
      _loadError =
          'Connexion serveur ACPEC requise pour partager un QR.';
    }
  }

  void _applyParent(QrToken? parent) {
    if (parent == null) {
      setState(() => _parent = null);
      return;
    }
    if (!AcpecQrSplitBuilder.canSplitParent(parent)) {
      setState(() {
        _parent = parent;
        _loadError =
            'Ce QR ne peut plus être partagé (état : ${parent.state.label}).';
      });
      return;
    }
    final initial = AcpecQrSplitBuilder.evenSplitTwoPartitions(parent);
    setState(() {
      _parent = parent;
      _partitions = initial.length >= 2 ? initial : [{}, {}];
      _loadError = null;
    });
  }

  Future<void> _loadParent() async {
    final user = context.read<AuthBloc>().state.user;
    setState(() {
      _loadingParent = true;
      _loadError = null;
    });
    try {
      final routeId = Uri.decodeComponent(widget.qrId);
      final detailParams = AcpecQrMapper.detailParamsForRouteId(routeId);
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        detailParams,
      );
      final raw = await OdooFueltokenFacade().qrDetail(detailParams);
      if (user == null) throw Exception('Session requise.');
      final q = AcpecQrMapper.fromRpcEnvelope(
        raw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      if (!mounted) return;
      setState(() => _loadingParent = false);
      _applyParent(q);
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _parent = null;
        _loadingParent = false;
        _loadError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parent = null;
        _loadingParent = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool get _isComplete {
    final p = _parent;
    if (p == null) return false;
    return AcpecQrSplitBuilder.isComplete(p, _partitions);
  }

  Future<void> _submit() async {
    final parent = _parent;
    if (parent == null || !AcpecQrSplitBuilder.canSplitParent(parent)) return;

    if (!_isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Répartissez tous les tickets du parent entre au moins deux parties.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (AppEnvironment.useAcpecLiveData) {
        final body = AcpecQrSplitBuilder.buildSplitRequest(
          parent: parent,
          partitionLinePicks: _partitions,
          idempotencyKey: 'ft-qr-split-${const Uuid().v4()}',
        );
        final raw = await OdooFueltokenFacade().qrSplit(body);
        AcpecQrMapper.assertSplitOk(raw);
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrDetail,
          AcpecQrMapper.detailParamsForRouteId(parent.publicCode),
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrList,
        );
      } else {
        throw Exception(
          'Connexion serveur ACPEC requise pour partager un QR.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR partagé avec succès.')),
        );
        context.pop();
      }
    } on AcpecQrSplitException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.message)),
        );
      }
    } on OdooJsonRpcException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              err.isOdooSessionExpired
                  ? 'Session expirée. Reconnectez-vous.'
                  : err.message,
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.useAcpecLiveData && _loadingParent) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppBarHeader(
                title: 'Partager le QR',
                subtitle: 'Chargement…',
                onBack: () => context.pop(),
              ),
              const Expanded(
                child: Center(child: AppLoadingLottie(size: 100)),
              ),
            ],
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _parent == null ? _loadParent : () => context.pop(),
                  child: Text(_parent == null ? 'Réessayer' : 'Retour'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final parent = _parent;
    if (parent == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('QR introuvable.'))),
      );
    }

    final code = Formatters.shortPublicCode(parent.publicCode);
    final totals = AcpecQrSplitBuilder.parentTotalsByFace(parent);
    final usedFace = AcpecQrSplitBuilder.usedByFaceFromPartitions(
      parent,
      _partitions,
    );
    final assigned = AcpecQrSplitBuilder.assignedTickets(_partitions);
    final total = AcpecQrSplitBuilder.totalTickets(parent);
    final ticketCounts = AcpecQrSplitBuilder.ticketExpiryCounts(parent);
    final sortedLines = AcpecQrSplitBuilder.sortedParentLines(parent);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppBarHeader(
              title: 'Partager le QR',
              subtitle: code,
              onBack: () => context.pop(),
              action: Material(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => setState(() => _partitions.add({})),
                  borderRadius: BorderRadius.circular(12),
                  child: const Tooltip(
                    message: 'Ajouter une partie',
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  if (parent.state == QrState.blocked)
                    _BlockedSplitHint(
                      valid: ticketCounts.valid,
                      expired: ticketCounts.expired,
                    ),
                  _SplitProgressCard(
                    assigned: assigned,
                    total: total,
                    usedByFace: usedFace,
                    totalsByFace: totals,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tickets du QR parent (carnets / lots)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.75,
                      color: AppColors.muted.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _partitions.length; i++) ...[
                    _PartitionCard(
                      index: i,
                      parent: parent,
                      sortedLines: sortedLines,
                      partitions: _partitions,
                      picks: _partitions[i],
                      onChange: (lineId, qty) => setState(() {
                        if (qty <= 0) {
                          _partitions[i].remove(lineId);
                        } else {
                          _partitions[i][lineId] = qty;
                        }
                      }),
                      onRemove: _partitions.length > 2
                          ? () => setState(() => _partitions.removeAt(i))
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 12,
        color: AppColors.ink,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _submitting || !_isComplete ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _submitting
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.45),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                icon: _submitting
                    ? const AppInlineLoading(size: 22)
                    : const Icon(Icons.call_split_rounded, size: 22),
                label: Text(
                  _isComplete
                      ? 'Confirmer le partage'
                      : 'Complétez la répartition',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedSplitHint extends StatelessWidget {
  const _BlockedSplitHint({
    required this.valid,
    required this.expired,
  });

  final int valid;
  final int expired;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Text(
          expired > 0
              ? 'QR bloqué : répartissez les $valid ticket${valid > 1 ? 's' : ''} valide${valid > 1 ? 's' : ''} '
                  'et les $expired expiré${expired > 1 ? 's' : ''} entre au moins deux parties '
                  '(un nouveau QR par partie).'
              : 'QR bloqué : affectez chaque ticket du parent à une partie '
                  '(même carnet ou carnets différents).',
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _SplitProgressCard extends StatelessWidget {
  const _SplitProgressCard({
    required this.assigned,
    required this.total,
    required this.usedByFace,
    required this.totalsByFace,
  });

  final int assigned;
  final int total;
  final Map<int, int> usedByFace;
  final Map<int, int> totalsByFace;

  @override
  Widget build(BuildContext context) {
    final complete = assigned == total && total > 0;
    final values = totalsByFace.keys.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tickets répartis',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.75,
                    color: AppColors.muted.withValues(alpha: 0.9),
                  ),
                ),
              ),
              Text(
                '$assigned / $total',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: complete ? AppColors.success : AppColors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                complete ? Icons.check_circle_rounded : Icons.pending_outlined,
                size: 20,
                color: complete
                    ? AppColors.success
                    : AppColors.hint.withValues(alpha: 0.75),
              ),
            ],
          ),
          if (values.length > 1) ...[
            const SizedBox(height: 10),
            for (final fv in values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${Formatters.numberFr(fv)} MRU : ${usedByFace[fv] ?? 0} / ${totalsByFace[fv]} ticket${totalsByFace[fv]! > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.body,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Une **partie** = futur QR après split ; l’utilisateur y affecte des tickets.
class _PartitionCard extends StatelessWidget {
  const _PartitionCard({
    required this.index,
    required this.parent,
    required this.sortedLines,
    required this.partitions,
    required this.picks,
    required this.onChange,
    this.onRemove,
  });

  final int index;
  final QrToken parent;
  final List<QrLine> sortedLines;
  final List<Map<String, int>> partitions;
  final Map<String, int> picks;
  final void Function(String lineId, int qty) onChange;
  final VoidCallback? onRemove;

  int _ticketsInPartition() =>
      picks.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final inPart = _ticketsInPartition();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partie ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        inPart > 0
                            ? '$inPart ticket${inPart > 1 ? 's' : ''} · nouveau QR'
                            : 'Sélectionnez les tickets à inclure',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.danger,
                    tooltip: 'Retirer cette partie',
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in sortedLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _TicketLineRow(
                  line: line,
                  value: picks[line.id] ?? 0,
                  max: AcpecQrSplitBuilder.maxForPartitionLine(
                    parent,
                    partitions,
                    index,
                    line.id,
                  ),
                  onChange: (n) => onChange(line.id, n),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TicketLineRow extends StatelessWidget {
  const _TicketLineRow({
    required this.line,
    required this.value,
    required this.max,
    required this.onChange,
  });

  final QrLine line;
  final int value;
  final int max;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final lot = line.lotInternalRef.trim();
    final hasLot = lot.isNotEmpty && lot != '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.qty} ticket${line.qty > 1 ? 's' : ''} · '
                  '${Formatters.numberFr(line.faceValue)} MRU',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.ink,
                  ),
                ),
                if (hasLot)
                  Text(
                    'Lot $lot',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted.withValues(alpha: 0.9),
                    ),
                  ),
                if (line.isExpired)
                  const Text(
                    'Expiré',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          _SplitStepper(
            value: value,
            max: max,
            onChange: onChange,
          ),
        ],
      ),
    );
  }
}

class _SplitStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChange;

  const _SplitStepper({
    required this.value,
    required this.max,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniStepBtn(
            icon: Icons.remove_rounded,
            enabled: value > 0,
            filled: false,
            onTap: () => onChange(value - 1),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          _MiniStepBtn(
            icon: Icons.add_rounded,
            enabled: value < max,
            filled: true,
            onTap: () => onChange(value + 1),
          ),
        ],
      ),
    );
  }
}

class _MiniStepBtn extends StatelessWidget {
  const _MiniStepBtn({
    required this.icon,
    required this.enabled,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.transparent
                : filled
                    ? AppColors.ink
                    : AppColors.lineSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 16,
            color: !enabled
                ? AppColors.hint
                : filled
                    ? Colors.white
                    : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
