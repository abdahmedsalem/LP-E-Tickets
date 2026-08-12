import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

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

class _QrDetailScreenState extends State<QrDetailScreen>
    with WidgetsBindingObserver {
  QrToken? _qr;
  bool _loading = false;
  bool _separating = false;
  bool _revealingManualCode = false;
  String? _revealedQrManualCode;
  static const Duration _manualCodeRevealDuration = Duration(seconds: 60);
  Timer? _manualCodeClearTimer;
  String? _error;
  late final VoidCallback _qrBusListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _manualCodeClearTimer?.cancel();
    _manualCodeClearTimer = null;
    _revealedQrManualCode = null;
    QrRefreshBus.instance.revision.removeListener(_qrBusListener);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _clearRevealedQrManualCode();
    }
  }

  void _clearRevealedQrManualCode() {
    _manualCodeClearTimer?.cancel();
    _manualCodeClearTimer = null;
    if (_revealedQrManualCode == null) return;
    if (!mounted) {
      _revealedQrManualCode = null;
      return;
    }
    setState(() => _revealedQrManualCode = null);
  }

  void _scheduleManualCodeAutoClear() {
    _manualCodeClearTimer?.cancel();
    _manualCodeClearTimer = Timer(_manualCodeRevealDuration, () {
      if (!mounted || _revealedQrManualCode == null) return;
      setState(() => _revealedQrManualCode = null);
    });
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _qr = null;
        _loading = false;
        _error = l10n.qrServerRequiredForDetail;
      });
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    _manualCodeClearTimer?.cancel();
    _manualCodeClearTimer = null;
    setState(() {
      _revealedQrManualCode = null;
      _loading = true;
      _error = null;
    });
    try {
      final params = AcpecQrMapper.detailParamsForRouteId(widget.qrId);
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        params,
      );
      final companyId = AppEnvironment.companyIdForUser(user);
      final detailFuture = OdooFueltokenFacade().qrDetail(params);
      final catalogFuture = AcpecCarnetCatalogService.instance
          .loadMobileCatalogFacesOnly(companyId: companyId)
          .catchError((_) => const AcpecCarnetCatalogLoadResult(types: []));
      final raw = await detailFuture;
      final catalogResult = await catalogFuture;
      final q = AcpecCarnetCatalogService.localizeQrTokenByCarnetTypes(
        qr: AcpecQrMapper.fromRpcEnvelope(
          raw,
          ownerId: user.id,
          ownerName: user.name,
          companyId: companyId,
        ),
        types: catalogResult.types,
      );
      if (!mounted) return;
      final previousPublicCode = _qr?.publicCode;
      setState(() {
        _qr = q;
        if (previousPublicCode != q.publicCode || q.state != QrState.active) {
          _revealedQrManualCode = null;
        }
        _loading = false;
        _error = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _qr = null;
        _loading = false;
        _error = e.isOdooSessionExpired
            ? l10n.sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qr = null;
        _loading = false;
        _error = ErrorPresenter.localizedMessage(context, e);
      });
    }
  }

  Future<void> _revealQrManualCode(QrToken qr) async {
    final l10n = AppLocalizations.of(context);
    if (_revealingManualCode) return;
    if (!AppEnvironment.useAcpecLiveData) {
      AppMessage.error(context, l10n.qrServerRequiredForManualCode);
      return;
    }
    if (qr.state != QrState.active) {
      AppMessage.error(context, l10n.qrManualCodeActiveOnly);
      return;
    }

    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: l10n.qrRevealManualCode,
      description: l10n.qrRevealManualCodeDescription,
    );
    if (actionCode == null || actionCode.isEmpty || !mounted) return;

    final intent = SensitiveActionIntent.create('qr-reveal-code');
    setState(() => _revealingManualCode = true);
    try {
      final raw = await OdooFueltokenFacade().qrRevealCode(
        intent.withAuthParams({
          'public_code': qr.publicCode,
        }, actionCode: actionCode),
      );
      final payload = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Révélation du code manuel refusée par le serveur.',
        publicErrorMessage: l10n.qrManualCodeRevealFailed,
      );
      final code =
          (payload['qr_numeric_code'] ?? payload['qrNumericCode'])
              ?.toString()
              .trim() ??
          '';
      if (code.isEmpty) {
        throw Exception('Code manuel non retourné par le serveur.');
      }
      if (!mounted) return;
      _manualCodeClearTimer?.cancel();
      setState(() => _revealedQrManualCode = code);
      _scheduleManualCodeAutoClear();
      AppMessage.success(context, l10n.qrManualCodeRevealed);
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      AppMessage.error(
        context,
        e.isOdooSessionExpired
            ? l10n.sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e),
      );
    } catch (e) {
      if (!mounted) return;
      AppMessage.error(context, ErrorPresenter.localizedMessage(context, e));
    } finally {
      if (mounted) setState(() => _revealingManualCode = false);
    }
  }

  Future<void> _separateBlockedQr(QrToken qr) async {
    final l10n = AppLocalizations.of(context);
    if (_separating) return;
    if (!AppEnvironment.useAcpecLiveData) {
      AppMessage.error(context, l10n.qrServerRequiredForSeparation);
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: l10n.commonPinVerification,
      description: l10n.commonPinConfirmationDescription,
    );
    if (actionCode == null || actionCode.isEmpty || !mounted) return;
    final intent = SensitiveActionIntent.create('qr-separer');
    setState(() => _separating = true);
    try {
      final raw = await OdooFueltokenFacade().qrSeparer(
        intent.withAuthParams({
          'public_code': qr.publicCode,
        }, actionCode: actionCode),
      );
      final payload = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Séparation QR refusée par le serveur.',
        publicErrorMessage: l10n.qrSeparationFailed,
      );
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
      AppMessage.success(context, l10n.qrSeparationSuccess);
      await _refresh();
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      AppMessage.error(
        context,
        e.isOdooSessionExpired
            ? l10n.sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e),
      );
    } catch (e) {
      if (!mounted) return;
      AppMessage.error(context, ErrorPresenter.localizedMessage(context, e));
    } finally {
      if (mounted) setState(() => _separating = false);
    }
  }

  ({String label, Color color}) _statePill(AppLocalizations l10n, QrState s) {
    switch (s) {
      case QrState.active:
        return (label: l10n.qrStatusActive, color: AppColors.leaderGreen);
      case QrState.blocked:
        return (label: l10n.qrStatusBlocked, color: const Color(0xFFF59E0B));
      case QrState.consumed:
        return (label: l10n.qrStatusConsumed, color: AppColors.muted);
      case QrState.expired:
        return (label: l10n.qrStatusExpired, color: AppColors.brandRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                title: l10n.qrDetailTitle,
                onBack: () => popOrGo(context, '/qr'),
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
              ScreenHeader(
                title: l10n.qrDetailTitle,
                onBack: () => popOrGo(context, '/qr'),
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
                        label: Text(l10n.commonRetry),
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
      return Scaffold(body: Center(child: Text(l10n.qrNotFound)));
    }
    final user = context.read<AuthBloc>().state.user!;
    final isOwner = user.id == qr.ownerId;
    final canRetirer =
        isOwner &&
        qr.state == QrState.active &&
        qr.lines.isNotEmpty &&
        qr.lines.length > 1;
    final canSeparer = isOwner && qr.state == QrState.blocked;
    final pill = _statePill(l10n, qr.state);
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
                          label: Text(l10n.qrWithdraw),
                          onPressed: () async {
                            final router = GoRouter.of(context);
                            final nextCode = await router.push<String>(
                              '/qr/$qrSeg/retirer',
                            );
                            if (!context.mounted) return;
                            if (nextCode != null && nextCode.isNotEmpty) {
                              router.go('/qr/${Uri.encodeComponent(nextCode)}');
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
                          label: Text(l10n.qrSeparateActiveButton),
                          onPressed: _separating
                              ? null
                              : () => _separateBlockedQr(qr),
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
            ScreenHeader(
              title: l10n.qrDetailTitle,
              onBack: () => popOrGo(context, '/qr'),
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
                        l10n.qrSeparateUsableHint,
                        style: TextStyle(
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
                    _HeroQrCard(
                      qr: qr,
                      pill: pill,
                      manualCode: _revealedQrManualCode,
                      revealingManualCode: _revealingManualCode,
                      onRevealManualCode: () => _revealQrManualCode(qr),
                    ),
                    const SizedBox(height: 22),
                    SectionLabel(l10n.qrContent),
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
  const _HeroQrCard({
    required this.qr,
    required this.pill,
    required this.manualCode,
    required this.revealingManualCode,
    required this.onRevealManualCode,
  });

  final QrToken qr;
  final ({String label, Color color}) pill;
  final String? manualCode;
  final bool revealingManualCode;
  final VoidCallback? onRevealManualCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isActive = qr.state == QrState.active;
    final showBadge = qr.state != QrState.active;
    final qrManualCode = manualCode?.trim() ?? '';
    final qrColor = switch (qr.state) {
      QrState.active => AppColors.ink,
      QrState.consumed => AppColors.muted,
      QrState.expired => AppColors.brandRed,
      QrState.blocked => AppColors.warning,
    };
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
                  QrImageView(
                    data: qr.publicCode,
                    version: QrVersions.auto,
                    size: 172,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: qrColor,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: qrColor,
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
          if (isActive) ...[
            _QrNumericCodePanel(
              code: qrManualCode,
              isActive: isActive,
              revealing: revealingManualCode,
              onReveal: onRevealManualCode,
            ),
            const SizedBox(height: 14),
          ],
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                _DetailInfoRow(
                  label: l10n.referenceCode,
                  value: qr.internalRef?.trim().isNotEmpty == true
                      ? qr.internalRef!.trim()
                      : qr.publicCode.trim().isNotEmpty
                      ? qr.publicCode.trim()
                      : l10n.notAvailable,
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.line),
                _DetailInfoRow(
                  label: l10n.expirationDate,
                  value: qr.expiresAt != null
                      ? Formatters.dateTimeDash(qr.expiresAt!)
                      : l10n.notAvailable,
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.line),
                _DetailInfoRow(
                  label: l10n.amount,
                  value: Formatters.money(qr.totalAmount),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrNumericCodePanel extends StatelessWidget {
  const _QrNumericCodePanel({
    required this.code,
    required this.isActive,
    required this.revealing,
    required this.onReveal,
  });

  final String code;
  final bool isActive;
  final bool revealing;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final revealed = code.trim().isNotEmpty;
    final codeColor = isActive && revealed ? AppColors.ink : AppColors.muted;
    final displayCode = revealed ? code.trim() : '••••-••••-••••';
    final helper = !isActive
        ? l10n.qrManualCodeActiveOnly
        : revealed
        ? l10n.qrManualCodeUsageHint
        : l10n.qrManualCodeHiddenHint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.qrManualCode,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 6),
              if (!revealed)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: l10n.qrRevealManualCode,
                    iconSize: 19,
                    color: AppColors.muted,
                    onPressed: revealing ? null : onReveal,
                    icon: revealing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_outlined),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            displayCode,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: codeColor,
              letterSpacing: 1.2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// Composition

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.qr});
  final QrToken qr;

  String _carnetLabel(QrLine line) {
    return Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
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

  String _title(AppLocalizations l10n) {
    final localizedLabel = label.trim();
    final carnetLabel = localizedLabel.isEmpty ? l10n.carnet : localizedLabel;
    return l10n.ticketsFromCarnet(line.qty, carnetLabel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isExpired = line.isExpired;
    return Container(
      color: isExpired ? const Color(0xFFF3F4F6) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleLineCardTitle(
                    text: _title(l10n),
                    style: TextStyle(
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
                  textAlign: TextAlign.end,
                  valueStyle: TextStyle(
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
                    line.isExpired
                        ? l10n.expiredOn(
                            Formatters.dateTimeDash(line.expirationDate),
                          )
                        : l10n.expiresOn(
                            Formatters.dateTimeDash(line.expirationDate),
                          ),
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
  const _DetailInfoRow({required this.label, required this.value});

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
                style: TextStyle(
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
                textAlign: TextAlign.end,
                style: TextStyle(
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
