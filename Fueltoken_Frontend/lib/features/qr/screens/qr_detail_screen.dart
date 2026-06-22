import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

const _detailHeaderPadding = EdgeInsets.fromLTRB(12, 8, 12, 0);
const _detailHeaderGap = 18.0;
const _detailHeaderTitleSize = 32.0;
const _headerNavy = Color(0xFF0F2747);

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
  bool _separating = false;
  String? _error;
  late final VoidCallback _qrBusListener;

  @override
  void initState() {
    super.initState();
    _loading = AppEnvironment.useAcpecLiveData;
    _qrBusListener = () {
      if (!mounted || !AppEnvironment.useAcpecLiveData) return;
      if (_loading) return;
      _refresh();
    };
    QrRefreshBus.instance.revision.addListener(_qrBusListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    QrRefreshBus.instance.revision.removeListener(_qrBusListener);
    super.dispose();
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

  Future<void> _separateBlockedQr(QrToken qr) async {
    if (_separating) return;
    if (!AppEnvironment.useAcpecLiveData) {
      AppMessage.error(
        context,
        'Connexion serveur ACPEC requise pour séparer un QR.',
      );
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: 'Vérification du PIN',
      description: 'Saisissez votre PIN pour confirmer cette opération.',
    );
    if (actionCode == null || actionCode.isEmpty || !mounted) return;
    setState(() => _separating = true);
    try {
      final raw = await OdooFueltokenFacade().qrSeparer({
        'public_code': qr.publicCode,
        'action_code': actionCode,
        'idempotency_key': 'ft-qr-separer-${const Uuid().v4()}',
      });
      if (raw is! Map) {
        throw Exception('Réponse QR invalide.');
      }
      final payload = raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : Map<String, dynamic>.from(raw);
      final newQrRaw = payload['new_qr'];
      final sourceRaw = payload['source'];

      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
      );
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        AcpecQrMapper.detailParamsForRouteId(qr.publicCode),
      );

      if (sourceRaw is Map) {
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrDetail,
          AcpecQrMapper.detailParamsForRouteId(qr.publicCode),
        );
      }

      if (newQrRaw is Map) {
        final userCompanyId = AppEnvironment.companyIdForUser(user);
        final child = AcpecQrMapper.fromRpcEnvelope(
          newQrRaw,
          ownerId: user.id,
          ownerName: user.name,
          companyId: userCompanyId,
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrDetail,
          AcpecQrMapper.detailParamsForRouteId(child.publicCode),
        );
      }

      QrRefreshBus.instance.bump();
      WalletRefreshBus.instance.bump();
      FacesRefreshBus.instance.bump();
      ClientHistoryRefreshBus.instance.bump();
      if (!mounted) return;
      AppMessage.success(context, 'QR séparé avec succès.');
      await _refresh();
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      AppMessage.error(
        context,
        e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message,
      );
    } catch (e) {
      if (!mounted) return;
      AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _separating = false);
    }
  }

  ({String label, Color color}) _statePill(QrState s) {
    switch (s) {
      case QrState.active:
        return (label: 'Actif', color: AppColors.leaderGreen);
      case QrState.blocked:
        return (label: 'BLOQUÉ', color: const Color(0xFFF59E0B));
      case QrState.consumed:
        return (label: 'CONSOMMÉ', color: AppColors.muted);
      case QrState.expired:
        return (label: 'EXPIRÉ', color: AppColors.brandRed);
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
              AppBarHeader(
                title: 'Détails du QR',
                onBack: () => context.pop(),
                largeTitle: true,
                largeTitlePadding: _detailHeaderPadding,
                largeTitleGap: _detailHeaderGap,
                largeTitleFontSize: _detailHeaderTitleSize,
                largeTitleTextStyle: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: _headerNavy,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
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
                title: 'Détails du QR',
                onBack: () => context.pop(),
                largeTitle: true,
                largeTitlePadding: _detailHeaderPadding,
                largeTitleGap: _detailHeaderGap,
                largeTitleFontSize: _detailHeaderTitleSize,
                largeTitleTextStyle: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: _headerNavy,
                  letterSpacing: -0.4,
                  height: 1.05,
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
        qr.lines.length > 1;
    final canSeparer = isOwner && qr.state == QrState.blocked;
    final pill = _statePill(qr.state);
    final scheme = Theme.of(context).colorScheme;
    final qrSeg = AppEnvironment.useAcpecLiveData
        ? Uri.encodeComponent(qr.publicCode)
        : qr.id;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: isOwner
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canRetirer)
                      SizedBox(
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
                          icon: const Icon(Icons.call_split, size: 18),
                          label: const Text('Retirer'),
                          onPressed: () async {
                            final router = GoRouter.of(context);
                            final nextCode = await router.push<String>(
                              '/qr/$qrSeg/retirer',
                            );
                            if (!context.mounted) return;
                            if (nextCode != null && nextCode.isNotEmpty) {
                              router.go(
                                '/qr/${Uri.encodeComponent(nextCode)}',
                              );
                            } else {
                              await _refresh();
                            }
                          },
                        ),
                      )
                    else if (canSeparer)
                      SizedBox(
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
                          icon: const Icon(Icons.call_split, size: 18),
                          label: const Text(
                            'Séparer la partie active dans un nouveau QR',
                          ),
                          onPressed: _separating ? null : () => _separateBlockedQr(qr),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: 'Détail QR Code',
              onBack: () => context.pop(),
              largeTitle: true,
              largeTitlePadding: _detailHeaderPadding,
              largeTitleGap: _detailHeaderGap,
              largeTitleFontSize: _detailHeaderTitleSize,
              largeTitleTextStyle: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: _headerNavy,
                letterSpacing: -0.4,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: RefreshIndicator(
                color: scheme.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    if (qr.state == QrState.blocked) ...[
                      Text(
                        'Séparez les tickets utilisables des tickets expirés.',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.muted,
                          height: 1.35,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Hero QR card
                    _HeroQrCard(qr: qr, pill: pill),
                    const SizedBox(height: 22),
                    const SectionLabel('Contenu'),
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

// Hero QR card

class _HeroQrCard extends StatelessWidget {
  const _HeroQrCard({required this.qr, required this.pill});
  final QrToken qr;
  final ({String label, Color color}) pill;

  @override
  Widget build(BuildContext context) {
    final isActive = qr.state == QrState.active;
    final showBadge = qr.state != QrState.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  ColorFiltered(
                    colorFilter: isActive
                        ? const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.dst,
                          )
                        : ColorFilter.matrix(_grayscale),
                    child: QrImageView(
                      data: qr.publicCode,
                      version: QrVersions.auto,
                      size: 172,
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
                  if (showBadge)
                    Positioned(
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: pill.color.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          pill.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                _DetailInfoRow(
                  label: 'Date d\'expiration',
                  value: qr.expiresAt != null
                      ? Formatters.dateTimeDash(qr.expiresAt!)
                      : 'Non disponible',
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.line),
                _DetailInfoRow(
                  label: 'Montant',
                  value: Formatters.money(qr.totalAmount),
                ),
              ],
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

// Composition

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.qr});
  final QrToken qr;

  int _carnetSizeFor(QrLine line) {
    if (line.carnetSize > 0) return line.carnetSize;

    final nameMatch = RegExp(r'\d+').firstMatch(line.carnetTypeName);
    if (nameMatch != null) {
      final parsed = int.tryParse(nameMatch.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final codeMatch = RegExp(r'\d+').firstMatch(line.carnetTypeCode);
    if (codeMatch != null) {
      final parsed = int.tryParse(codeMatch.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    return 0;
  }

  String _carnetLabel(QrLine line) {
    final carnetSize = _carnetSizeFor(line);
    return Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackSize: carnetSize,
      fallbackFaceValue: line.faceValue,
      fallbackCode: line.carnetTypeCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = qr.lines.toList()
      ..sort((a, b) {
        final byDate = a.expirationDate.compareTo(b.expirationDate);
        if (byDate != 0) return byDate;
        if (a.faceValue != b.faceValue) {
          return b.faceValue.compareTo(a.faceValue);
        }
        return a.id.compareTo(b.id);
      });
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.lineSoft),
            _CompositionLineRow(label: _carnetLabel(lines[i]), line: lines[i]),
          ],
        ],
      ),
    );
  }
}

class _CompositionLineRow extends StatelessWidget {
  const _CompositionLineRow({required this.label, required this.line});

  final String label;
  final QrLine line;

  String _title() {
    final qtyLabel =
        '${Formatters.numberFr(line.qty)} ticket${line.qty > 1 ? 's' : ''}';
    final cleanLabel = label.replaceFirst(
      RegExp(r'^\s*Carnet\s+', caseSensitive: false),
      '',
    );
    return '$qtyLabel de carnet $cleanLabel';
  }

  String _dateLabel() => line.isExpired ? 'Expirée le' : 'Expire le';

  @override
  Widget build(BuildContext context) {
    final isExpired = line.isExpired;
    return Container(
      color: isExpired ? const Color(0xFFF3F4F6) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _title(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AmountInline(
                  amount: line.amount,
                  textAlign: TextAlign.right,
                  valueStyle: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                  unitStyle: const TextStyle(color: AppColors.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${_dateLabel()} ${Formatters.dateTimeDash(line.expirationDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 7,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
