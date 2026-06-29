import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

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
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _parent = null;
        _loading = false;
        _error = 'Connexion serveur ACPEC requise pour retirer un QR.';
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
      final raw = await OdooFueltokenFacade().qrDetail(params);
      final qr = AcpecQrMapper.fromRpcEnvelope(
        raw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      if (!mounted) return;
      if (qr.state != QrState.active) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = 'Seuls les QR actifs peuvent être retirés.';
        });
        return;
      }
      if (qr.lines.length <= 1) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = 'Un QR contenant une seule ligne ne peut pas être retiré.';
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
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parent = null;
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _toggleLineSelection(String lineId) {
    setState(() {
      if (_selectedLineIds.contains(lineId)) {
        _selectedLineIds.remove(lineId);
      } else {
        _selectedLineIds.add(lineId);
      }
    });
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
    final parent = _parent;
    if (parent == null ||
        parent.state != QrState.active ||
        parent.lines.length <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception('Session requise.');

    final picks = <Map<String, dynamic>>[];
    for (final line in _selectedLines(parent)) {
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de ligne QR manquant. Rechargez le QR.',
        );
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': line.qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, 'Sélectionnez au moins une ligne à retirer.');
      return;
    }

    await _performSubmit();
  }

  Future<void> _performSubmit() async {
    final parent = _parent;
    if (parent == null ||
        parent.state != QrState.active ||
        parent.lines.length <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception('Session requise.');

    final picks = <Map<String, dynamic>>[];
    for (final line in _selectedLines(parent)) {
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de ligne QR manquant. Rechargez le QR.',
        );
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': line.qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, 'Sélectionnez au moins une ligne à retirer.');
      return;
    }

    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: 'Vérification du PIN',
      description: 'Saisissez votre PIN pour confirmer cette opération.',
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
        publicErrorMessage:
            'Le retrait du QR a échoué. Réessayez ou contactez l’administrateur.',
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
      AppMessage.success(context, 'QR retiré avec succès.');
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
            ? 'Session expirée. Reconnectez-vous.'
            : e.message,
      );
    } catch (e) {
      if (!mounted) return;
      AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              ScreenHeader(
                title: 'Retirer',
                onBack: () => context.pop(),
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
                      : () => context.pop(),
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
      return const Scaffold(body: Center(child: Text('QR introuvable.')));
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
                    ? 'Retrait...'
                    : selectedLineCount > 0
                    ? 'Retirer ($selectedLineCount)'
                    : 'Retirer',
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Retirer',
              onBack: () => context.pop(),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Text(
                    'Sélectionnez les lignes à retirer.',
                    style: GoogleFonts.poppins(
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
                                'Sélection',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$selectedLineCount ligne${selectedLineCount > 1 ? 's' : ''} sélectionnée${selectedLineCount > 1 ? 's' : ''}',
                                style: GoogleFonts.poppins(
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
                              style: GoogleFonts.poppins(
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
                            style: GoogleFonts.poppins(
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
    final borderColor = selected
        ? AppColors.leaderGreen.withValues(alpha: 0.42)
        : const Color(0xFFE8EAED);
    final bgColor = selected ? AppColors.successSurface : Colors.white;
    final lineTitle =
        '${Formatters.numberFr(line.qty)} ticket${line.qty > 1 ? 's' : ''} '
        'de carnet ${Formatters.numberFr(line.carnetSize > 0 ? line.carnetSize : line.qty)} × '
        '${Formatters.numberFr(line.faceValue)}';

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
                          child: Text(
                            lineTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
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
                      'Expire le ${Formatters.dateTimeDash(line.expirationDate)}',
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
