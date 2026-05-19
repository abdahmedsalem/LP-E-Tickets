import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/icon_btn.dart';
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
        _error =
            'Connexion serveur ACPEC requise pour afficher ce QR.';
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
        body: SafeArea(
          child: Column(
            children: [
              AppBarHeader(
                title: 'Détail du QR',
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
    if (_error != null) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppBarHeader(
                title: 'Détail du QR',
                subtitle: 'Erreur',
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
                    Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
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
    final canSplit = isOwner &&
        (qr.state == QrState.active || qr.state == QrState.blocked);
    final pill = _statePill(qr.state);
    final scheme = Theme.of(context).colorScheme;
    final splitSeg = AppEnvironment.useAcpecLiveData
        ? Uri.encodeComponent(qr.publicCode)
        : qr.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: canSplit
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      await context.push('/qr/$splitSeg/split');
                      await _refresh();
                    },
                    icon: const Icon(Icons.call_split, size: 18),
                    label: const Text('Splitter ce QR'),
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
              subtitle: Formatters.shortPublicCode(qr.publicCode),
              onBack: () => context.pop(),
              action: IconBtn(
                icon: Icons.refresh_rounded,
                onPressed: _refresh,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: scheme.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (widget.justEmitted)
                      _QrEmitSuccessSummary(qr: qr, pill: pill),
                    if (qr.state == QrState.blocked) const _BlockedBanner(),
                    if (qr.state == QrState.consumed)
                      _ConsumedBanner(qr: qr),
                    if (qr.state == QrState.expired) const _ExpiredBanner(),
                    if (qr.state == QrState.split) const _SplitBanner(),

                    // ── Hero QR card ──
                    _HeroQrCard(
                      qr: qr,
                      pill: pill,
                      simplifyHeader: widget.justEmitted,
                    ),

                    const SizedBox(height: 18),

                    const SectionLabel('Composition'),
                    const SizedBox(height: 8),
                    _CompositionCard(qr: qr),

                    if (!widget.justEmitted) ...[
                      const SizedBox(height: 18),
                      const SectionLabel('Informations'),
                      const SizedBox(height: 8),
                      _QrInfoCard(qr: qr),
                    ],

                    if (qr.lines.isNotEmpty && qr.hasAuditableLotOrigins) ...[
                      const SizedBox(height: 18),
                      const SectionLabel('Origine des tickets'),
                      const SizedBox(height: 8),
                      _LotsCard(qr: qr),
                    ],

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
  const _HeroQrCard({
    required this.qr,
    required this.pill,
    this.simplifyHeader = false,
  });
  final QrToken qr;
  final ({String label, PillTone tone}) pill;
  final bool simplifyHeader;

  @override
  Widget build(BuildContext context) {
    final isActive = qr.state == QrState.active;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (!simplifyHeader)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lineSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${qr.id.substring(0, qr.id.length.clamp(0, 6)).toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                )
              else
                Text(
                  'Prêt à l’usage',
                  style: TextStyle(
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
                          Colors.transparent, BlendMode.dst)
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
                        horizontal: 18, vertical: 8),
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
          Text(
            Formatters.shortPublicCode(qr.publicCode),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.body,
            ),
          ),
          const SizedBox(height: 18),
          // Greentint summary block
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primarySoft),
            ),
            child: Column(
              children: [
                Text(
                  Formatters.numberFr(qr.totalAmount),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'MRU',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${qr.totalQty} ticket${qr.totalQty > 1 ? 's' : ''} · ${qr.aggregatedByFaceValue.length} valeur${qr.aggregatedByFaceValue.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<double> _grayscale = [
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// ──────────────────────────────────────────────────────────────────────────
// Composition / tech / lots
// ──────────────────────────────────────────────────────────────────────────

class _QrInfoCard extends StatelessWidget {
  const _QrInfoCard({required this.qr});

  final QrToken qr;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.qr_code_2_rounded,
            label: 'Code public',
            value: qr.publicCode,
            mono: true,
            trailing: IconButton(
              tooltip: 'Copier',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: qr.publicCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copié.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
          ),
          _InfoRow(
            icon: Icons.flag_outlined,
            label: 'Statut',
            value: qr.state.label,
          ),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'Émis le',
            value: Formatters.dateTime(qr.createdAt),
          ),
          _InfoRow(
            icon: Icons.person_outline,
            label: 'Propriétaire',
            value: qr.ownerName,
          ),
          if (qr.consumedAt != null)
            _InfoRow(
              icon: Icons.local_gas_station_outlined,
              label: 'Consommé le',
              value: Formatters.dateTime(qr.consumedAt!),
            ),
          if (qr.consumedByStationName != null &&
              qr.consumedByStationName!.trim().isNotEmpty)
            _InfoRow(
              icon: Icons.storefront_outlined,
              label: 'Station',
              value: qr.consumedByStationName!.trim(),
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
    this.mono = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
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
                  style: (mono ? GoogleFonts.jetBrainsMono : GoogleFonts.inter)(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

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

class _LotsCard extends StatelessWidget {
  const _LotsCard({required this.qr});
  final QrToken qr;

  @override
  Widget build(BuildContext context) {
    final byLot = <String, List<QrLine>>{};
    for (final l in qr.lines) {
      byLot.putIfAbsent(l.lotInternalRef, () => []).add(l);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < byLot.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.lineSoft),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Lot ${byLot.keys.elementAt(i)}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Expire le ${Formatters.date(byLot.values.elementAt(i).first.expirationDate)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: byLot.values.elementAt(i).first.isExpired
                              ? AppColors.danger
                              : AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final l in byLot.values.elementAt(i))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.fiber_manual_record,
                              size: 6, color: AppColors.hint),
                          const SizedBox(width: 6),
                          Text(
                            '${l.qty} ticket${l.qty > 1 ? 's' : ''} · ${Formatters.numberFr(l.faceValue)} MRU',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.body,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            Formatters.numberFr(l.amount),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
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

// ──────────────────────────────────────────────────────────────────────────
// Résumé émission (API issue : public_code, state, amount_total)
// ──────────────────────────────────────────────────────────────────────────

class _QrEmitSuccessSummary extends StatelessWidget {
  const _QrEmitSuccessSummary({
    required this.qr,
    required this.pill,
  });

  final QrToken qr;
  final ({String label, PillTone tone}) pill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
        boxShadow: AppColors.softShadow,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.brandBlueMid.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: scheme.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'QR émis avec succès',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Présentez ce code à la station. Vous pouvez copier le code ci-dessous ou le scanner depuis l’écran.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.muted.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _EmitSummaryRow(
              label: 'État',
              child: AppPill(label: pill.label, tone: pill.tone),
            ),
            const SizedBox(height: 12),
            _EmitSummaryRow(
              label: 'Montant total',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    Formatters.numberFr(qr.totalAmount),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'MRU',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted.withValues(alpha: 0.9),
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
}

class _EmitSummaryRow extends StatelessWidget {
  const _EmitSummaryRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.75,
            color: AppColors.muted.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Banners
// ──────────────────────────────────────────────────────────────────────────

class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner();
  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.warning,
      bg: AppColors.warningSurface,
      border: AppColors.warning,
      title: 'QR bloqué',
      message:
          'Contient des tickets expirés et des tickets valides. Splittez-le pour isoler les tickets utilisables.',
    );
  }
}

class _ConsumedBanner extends StatelessWidget {
  const _ConsumedBanner({required this.qr});
  final QrToken qr;
  @override
  Widget build(BuildContext context) {
    final msg = qr.consumedAt == null
        ? 'QR consommé.'
        : 'Consommé le ${Formatters.dateTime(qr.consumedAt!)} · ${qr.consumedByStationName ?? '—'}';
    return _Banner(
      icon: Icons.local_gas_station_outlined,
      iconColor: AppColors.muted,
      bg: AppColors.lineSoft,
      border: AppColors.line,
      title: 'QR consommé',
      message: msg,
    );
  }
}

class _ExpiredBanner extends StatelessWidget {
  const _ExpiredBanner();
  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: Icons.schedule,
      iconColor: AppColors.danger,
      bg: AppColors.dangerSurface,
      border: AppColors.danger,
      title: 'QR expiré',
      message: 'Aucun remboursement n\'est possible.',
    );
  }
}

class _SplitBanner extends StatelessWidget {
  const _SplitBanner();
  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: Icons.call_split,
      iconColor: AppColors.info,
      bg: AppColors.infoSurface,
      border: AppColors.info,
      title: 'QR splitté',
      message:
          'Conservé uniquement pour audit, plus utilisable pour un achat.',
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.border,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Color border;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.body,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
