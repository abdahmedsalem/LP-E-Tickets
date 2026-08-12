import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
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
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../../shared/widgets/single_line_card_title.dart';

class RetirerQrScreen extends StatefulWidget {
  const RetirerQrScreen({super.key, required this.qrId});

  final String qrId;

  @override
  State<RetirerQrScreen> createState() => _RetirerQrScreenState();
}

class _RetirerQrScreenState extends State<RetirerQrScreen> {
  QrToken? _parent;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  final Set<String> _selectedLineIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loading = AppEnvironment.useAcpecLiveData;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParent());
  }

  Future<void> _loadParent() async {
    final l10n = AppLocalizations.of(context);
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _parent = null;
        _loading = false;
        _error = l10n.qrServerRequiredForWithdrawal;
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
      final routeId = Uri.decodeComponent(widget.qrId);
      final params = AcpecQrMapper.detailParamsForRouteId(routeId);
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
      final qr = AcpecCarnetCatalogService.localizeQrTokenByCarnetTypes(
        qr: AcpecQrMapper.fromRpcEnvelope(
          raw,
          ownerId: user.id,
          ownerName: user.name,
          companyId: companyId,
        ),
        types: catalogResult.types,
      );
      if (!mounted) return;
      if (qr.state != QrState.active) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = l10n.qrOnlyActiveCanWithdraw;
        });
        return;
      }
      if (qr.lines.length <= 1) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = l10n.qrSingleLineCannotWithdraw;
        });
        return;
      }
      _selectedLineIds.clear();
      setState(() {
        _parent = qr;
        _loading = false;
        _error = null;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _parent = null;
        _loading = false;
        _error = e.isOdooSessionExpired
            ? l10n.sessionExpiredReconnect
            : ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parent = null;
        _loading = false;
        _error = ErrorPresenter.localizedMessage(context, e);
      });
    }
  }

  void _toggleLineSelection(String lineId) {
    final parent = _parent;
    if (parent == null) return;

    final nextSelection = Set<String>.of(_selectedLineIds);
    if (!nextSelection.remove(lineId)) {
      nextSelection.add(lineId);
      if (_wouldWithdrawAllLines(parent, nextSelection)) {
        AppMessage.warning(
          context,
          AppLocalizations.of(context).qrKeepAtLeastOneLine,
        );
        return;
      }
    }

    setState(() {
      _selectedLineIds
        ..clear()
        ..addAll(nextSelection);
    });
  }

  bool _wouldWithdrawAllLines(QrToken parent, Set<String> selectedLineIds) {
    return parent.lines.isNotEmpty &&
        parent.lines.every((line) => selectedLineIds.contains(line.id));
  }

  List<QrLine> _selectedLines(QrToken parent) {
    return parent.lines
        .where((line) => _selectedLineIds.contains(line.id))
        .toList(growable: false);
  }

  int _selectedAmount(QrToken parent) {
    var total = 0;
    for (final line in _selectedLines(parent)) {
      total += line.qty * line.faceValue;
    }
    return total;
  }

  /// Retourne l'identifiant entier de la ligne QR à envoyer à l'API.
  int? _qrLineIdForApi(QrLine line) {
    for (final raw in [line.id, line.faceLineId]) {
      final n = int.tryParse(raw.trim());
      if (n != null) return n;
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final parent = _parent;
    if (parent == null ||
        parent.state != QrState.active ||
        parent.lines.length <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception(l10n.commonSessionRequired);

    final picks = <Map<String, dynamic>>[];
    for (final line in _selectedLines(parent)) {
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(context, l10n.qrMissingLineIdentifier);
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': line.qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, l10n.qrSelectAtLeastOneLine);
      return;
    }
    if (_wouldWithdrawAllLines(parent, _selectedLineIds)) {
      AppMessage.warning(context, l10n.qrKeepAtLeastOneLine);
      return;
    }

    await _performSubmit();
  }

  Future<void> _performSubmit() async {
    final l10n = AppLocalizations.of(context);
    final parent = _parent;
    if (parent == null ||
        parent.state != QrState.active ||
        parent.lines.length <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception(l10n.commonSessionRequired);

    final picks = <Map<String, dynamic>>[];
    for (final line in _selectedLines(parent)) {
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(context, l10n.qrMissingLineIdentifier);
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': line.qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, l10n.qrSelectAtLeastOneLine);
      return;
    }
    if (_wouldWithdrawAllLines(parent, _selectedLineIds)) {
      AppMessage.warning(context, l10n.qrKeepAtLeastOneLine);
      return;
    }

    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: l10n.commonPinVerification,
      description: l10n.commonPinConfirmationDescription,
    );
    if (actionCode == null || actionCode.isEmpty || !mounted) return;

    final intent = SensitiveActionIntent.create('qr-retirer');
    setState(() => _submitting = true);
    try {
      final raw = await OdooFueltokenFacade().qrRetirer(
        intent.withAuthParams({
          'public_code': parent.publicCode,
          'lines': picks,
        }, actionCode: actionCode),
      );
      final payload = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Retrait QR refusé par le serveur.',
        publicErrorMessage: l10n.qrWithdrawalFailed,
      );

      final newQrRaw = payload['new_qr'];
      final sourceRaw = payload['source'];

      if (sourceRaw is Map) {
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrDetail,
          AcpecQrMapper.detailParamsForRouteId(parent.publicCode),
        );
      }
      if (newQrRaw is Map) {
        final companyId = AppEnvironment.companyIdForUser(user);
        final child = AcpecQrMapper.fromRpcEnvelope(
          newQrRaw,
          ownerId: user.id,
          ownerName: user.name,
          companyId: companyId,
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrDetail,
          AcpecQrMapper.detailParamsForRouteId(child.publicCode),
        );
      }
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
      );
      if (!mounted) return;
      AppMessage.success(context, l10n.qrWithdrawalSuccess);
      QrRefreshBus.instance.bump();
      WalletRefreshBus.instance.bump();
      FacesRefreshBus.instance.bump();
      ClientHistoryRefreshBus.instance.bump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      context.go('/qr');
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
      if (mounted) setState(() => _submitting = false);
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
                title: l10n.qrWithdrawTitle,
                onBack: () => popOrGo(context, '/qr'),
              ),
              const SizedBox(height: 18),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: AppLoadingSkeleton(
                    style: AppLoadingSkeletonStyle.qrGeneration,
                    itemCount: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _parent == null
                      ? _loadParent
                      : () => popOrGo(context, '/qr'),
                  child: Text(
                    _parent == null ? l10n.commonRetry : l10n.commonBack,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final parent = _parent;
    if (parent == null) {
      return Scaffold(body: Center(child: Text(l10n.qrNotFound)));
    }

    final selectedLineCount = _selectedLines(parent).length;
    final selectedAmount = _selectedAmount(parent);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
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
              onPressed: _submitting || selectedLineCount <= 0 ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split_rounded, size: 18),
              label: Text(
                _submitting
                    ? l10n.qrWithdrawalInProgress
                    : selectedLineCount > 0
                    ? l10n.qrWithdrawSelected(selectedLineCount)
                    : l10n.qrWithdraw,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: l10n.qrWithdrawTitle,
              onBack: () => popOrGo(context, '/qr'),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Text(
                    l10n.qrWithdrawInstruction,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in parent.lines) ...[
                    _RetirerLineCard(
                      line: line,
                      selected: _selectedLineIds.contains(line.id),
                      onTap: () => _toggleLineSelection(line.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.selection,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.selectedLines(selectedLineCount),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Formatters.numberFr(selectedAmount),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                height: 1,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              Formatters.defaultCurrency,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.successSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$selectedLineCount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.leaderGreenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetirerLineCard extends StatelessWidget {
  const _RetirerLineCard({
    required this.line,
    required this.selected,
    required this.onTap,
  });

  final QrLine line;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final borderColor = selected
        ? AppColors.leaderGreen.withValues(alpha: 0.42)
        : const Color(0xFFE8EAED);
    final bgColor = selected ? AppColors.successSurface : Colors.white;
    final serverLabel = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    final carnetLabel = serverLabel.isEmpty ? l10n.carnet : serverLabel;
    final lineTitle = l10n.ticketsFromCarnet(line.qty, carnetLabel);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleLineCardTitle(
                            text: lineTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.08,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: selected
                              ? AppColors.leaderGreen
                              : AppColors.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.expiresOn(
                        Formatters.dateTimeDash(line.expirationDate),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                        height: 1.08,
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
