import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/icon_btn.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/bloc/auth_bloc.dart';

class QrDetailScreen extends StatefulWidget {
  final String qrId;
  final bool justEmitted;
  const QrDetailScreen({
    super.key,
    required this.qrId,
    this.justEmitted = false,
  });
  @override
  State<QrDetailScreen> createState() => _QrDetailScreenState();
}

class _QrDetailScreenState extends State<QrDetailScreen> {
  QrToken? _qr;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = AppEnvironment.useAcpecLiveData;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _qr = null;
        _loading = false;
        _error = 'Connexion serveur ACPEC requise pour afficher ce QR.';
      });
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = AcpecQrMapper.detailParamsForRouteId(widget.qrId);
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        params,
      );
      final raw = await OdooFueltokenFacade().qrDetail(params);
      final q = AcpecQrMapper.fromRpcEnvelope(
        raw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      if (!mounted) return;
      setState(() {
        _qr = q;
        _loading = false;
        _error = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _qr = null;
        _loading = false;
        _error = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qr = null;
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  ({String label, PillTone tone}) _statePill(QrState s) {
    switch (s) {
      case QrState.active:
        return (label: 'Actif', tone: PillTone.green);
      case QrState.blocked:
        return (label: 'Bloqué', tone: PillTone.amber);
      case QrState.consumed:
        return (label: 'Consommé', tone: PillTone.gray);
      case QrState.expired:
        return (label: 'Expiré', tone: PillTone.red);
      case QrState.split:
        return (label: 'Splitté', tone: PillTone.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              AppBarHeader(title: 'Détail du QR', onBack: () => context.pop()),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: AppLoadingSkeleton(
                    style: AppLoadingSkeletonStyle.qrCards,
                    itemCount: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppBarHeader(
                title: 'Détail du QR',
                onBack: () => context.pop(),
                action: IconBtn(
                  icon: Icons.refresh_rounded,
                  onPressed: _refresh,
                ),
              ),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
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
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Réessayer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final qr = _qr;
    if (qr == null) {
      return const Scaffold(body: Center(child: Text('QR introuvable.')));
    }
    final user = context.read<AuthBloc>().state.user!;
    final isOwner = user.id == qr.ownerId;
    final canRetirer =
        isOwner &&
        qr.state == QrState.active &&
        qr.lines.isNotEmpty &&
        qr.totalQty > 1;
    final canSeparer = isOwner && qr.state == QrState.blocked;
    final pill = _statePill(qr.state);
    final scheme = Theme.of(context).colorScheme;
    final qrSeg = AppEnvironment.useAcpecLiveData
        ? Uri.encodeComponent(qr.publicCode)
        : qr.id;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: canRetirer || canSeparer
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8F3A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF1B8F3A,
                      ).withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      final nextCode = canRetirer
                          ? await router.push<String>('/qr/$qrSeg/retirer')
                          : await router.push<String>('/qr/$qrSeg/separer');
                      if (!context.mounted) return;
                      if (nextCode != null && nextCode.isNotEmpty) {
                        router.go('/qr/${Uri.encodeComponent(nextCode)}');
                      } else {
                        await _refresh();
                      }
                    },
                    icon: Icon(
                      canRetirer ? Icons.call_split : Icons.unfold_more,
                      size: 18,
                    ),
                    label: Text(canRetirer ? 'Retirer' : 'Séparer'),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: 'Détail du QR',
              onBack: () => context.pop(),
              action: IconBtn(icon: Icons.refresh_rounded, onPressed: _refresh),
            ),
            Expanded(
              child: RefreshIndicator(
                color: scheme.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    // ── Hero QR card ──
                    _HeroQrCard(qr: qr, pill: pill),
                    const SizedBox(height: 22),

                    const SectionLabel('Composition'),
                    const SizedBox(height: 8),
                    _CompositionCard(qr: qr),

                    const SizedBox(height: 24),
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

// ──────────────────────────────────────────────────────────────────────────
// Hero QR card
// ──────────────────────────────────────────────────────────────────────────

class _HeroQrCard extends StatelessWidget {
  const _HeroQrCard({required this.qr, required this.pill});
  final QrToken qr;
  final ({String label, PillTone tone}) pill;

  @override
  Widget build(BuildContext context) {
    final isActive = qr.state == QrState.active;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Généré le ${Formatters.dateTime(qr.generatedAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              AppPill(
                label: pill.label,
                tone: pill.tone,
                dot: true,
                size: AppPillSize.lg,
              ),
            ],
          ),
          const SizedBox(height: 18),
          // QR with corner brackets
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: ColorFiltered(
                  colorFilter: isActive
                      ? const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        )
                      : ColorFilter.matrix(_grayscale),
                  child: QrImageView(
                    data: qr.publicCode,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              if (qr.state == QrState.consumed)
                Transform.rotate(
                  angle: -0.12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.muted.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'CONSOMMÉ',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primarySoft),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Montant',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                Text(
                  '${Formatters.numberFr(qr.totalAmount)} MRU',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              qr.state == QrState.consumed && qr.consumedAt != null
                  ? 'Consommé le ${Formatters.dateTime(qr.consumedAt!)}'
                  : qr.state == QrState.expired && qr.expiresAt != null
                  ? 'Expiré le ${Formatters.dateTime(qr.expiresAt!)}'
                  : qr.expiresAt != null
                  ? 'Expire le ${Formatters.dateTime(qr.expiresAt!)}'
                  : 'Date de génération: ${Formatters.dateTime(qr.generatedAt)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<double> _grayscale = [
    0.33,
    0.33,
    0.33,
    0,
    0,
    0.33,
    0.33,
    0.33,
    0,
    0,
    0.33,
    0.33,
    0.33,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

// ──────────────────────────────────────────────────────────────────────────
// Composition
// ──────────────────────────────────────────────────────────────────────────

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.qr});
  final QrToken qr;

  @override
  Widget build(BuildContext context) {
    final entries = qr.aggregatedByFaceValue.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.lineSoft),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  FaceValueChip(value: entries[i].key),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${entries[i].value} ticket${entries[i].value > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.money(entries[i].key * entries[i].value),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
