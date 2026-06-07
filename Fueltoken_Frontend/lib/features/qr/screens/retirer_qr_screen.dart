import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

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
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import 'qr_action_confirmation_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

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
  final Map<String, int> _selectedQty = <String, int>{};

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
      if (qr.totalQty <= 1) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = 'Un QR contenant un seul ticket ne peut pas être retiré.';
        });
        return;
      }
      _selectedQty
        ..clear()
        ..addEntries(qr.lines.map((line) => MapEntry(line.id, 0)));
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

  void _setQty(String lineId, int value, int max) {
    final clamped = value.clamp(0, max).toInt();
    setState(() => _selectedQty[lineId] = clamped);
  }

  int _selectedTickets(QrToken parent) {
    var total = 0;
    for (final line in parent.lines) {
      total += (_selectedQty[line.id] ?? 0);
    }
    return total;
  }

  int _selectedAmount(QrToken parent) {
    var total = 0;
    for (final line in parent.lines) {
      final qty = _selectedQty[line.id] ?? 0;
      total += qty * line.faceValue;
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
        parent.totalQty <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception('Session requise.');

    final picks = <Map<String, dynamic>>[];
    for (final line in parent.lines) {
      final qty = _selectedQty[line.id] ?? 0;
      if (qty <= 0) continue;
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de ligne QR manquant. Rechargez le QR.',
        );
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, 'Sélectionnez au moins une ligne à retirer.');
      return;
    }

    final selectedTickets = _selectedTickets(parent);
    final selectedAmount = _selectedAmount(parent);
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QrActionConfirmationScreen(
          args: QrActionConfirmationArgs(
            title: 'Confirmer le retrait',
            subtitle: 'Retrait de carnets depuis ce QR',
            confirmLabel: 'Confirmer le retrait',
            hero: _RetirerConfirmationHero(
              qrCode: parent.publicCode,
              selectedTickets: selectedTickets,
              selectedAmount: selectedAmount,
            ),
            summaryRows: [
              QrActionSummaryRow(
                label: 'Montant à retirer',
                value: '${Formatters.numberFr(selectedAmount)} MRU',
                valueColor: const Color(0xFF1B8F3A),
              ),
            ],
            disclaimer: 'Le retrait est définitif après confirmation.',
          ),
        ),
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      await _performSubmit();
    }
  }

  Future<void> _performSubmit() async {
    final parent = _parent;
    if (parent == null ||
        parent.state != QrState.active ||
        parent.totalQty <= 1) {
      return;
    }
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception('Session requise.');

    final picks = <Map<String, dynamic>>[];
    for (final line in parent.lines) {
      final qty = _selectedQty[line.id] ?? 0;
      if (qty <= 0) continue;
      final qrLineId = _qrLineIdForApi(line);
      if (qrLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de ligne QR manquant. Rechargez le QR.',
        );
        return;
      }
      picks.add({'qr_line_id': qrLineId, 'qty': qty});
    }

    if (picks.isEmpty) {
      AppMessage.warning(context, 'Sélectionnez au moins une ligne à retirer.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final raw = await OdooFueltokenFacade().qrRetirer({
        'public_code': parent.publicCode,
        'lines': picks,
        'idempotency_key': 'ft-qr-retirer-${const Uuid().v4()}',
      });
      if (raw is! Map) {
        throw Exception('Réponse QR invalide.');
      }
      final payload = raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : Map<String, dynamic>.from(raw);

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
              AppBarHeader(
                title: 'Retirer du QR',
                onBack: () => context.pop(),
                plainBackButton: true,
              ),
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

    final selectedTickets = _selectedTickets(parent);
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
              onPressed: _submitting || selectedTickets <= 0 ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split_rounded, size: 18),
              label: Text(_submitting ? 'Retrait...' : 'Retirer'),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: 'Retirer du QR',
              onBack: () => context.pop(),
              plainBackButton: true,
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  const SectionLabel('Lignes à retirer'),
                  const SizedBox(height: 8),
                  for (final line in parent.lines) ...[
                    _RetirerLineCard(
                      line: line,
                      qty: _selectedQty[line.id] ?? 0,
                      onDecrement: () => _setQty(
                        line.id,
                        (_selectedQty[line.id] ?? 0) - 1,
                        line.qty,
                      ),
                      onIncrement: () => _setQty(
                        line.id,
                        (_selectedQty[line.id] ?? 0) + 1,
                        line.qty,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sélection',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        Text(
                          '$selectedTickets ticket${selectedTickets > 1 ? 's' : ''} · ${Formatters.numberFr(selectedAmount)} MRU',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
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
    required this.qty,
    required this.onDecrement,
    required this.onIncrement,
  });

  final QrLine line;
  final int qty;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  int get _max => line.qty;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carnet ${Formatters.numberFr(line.qty)} × ${Formatters.numberFr(line.faceValue)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.08,
                      ),
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
              const SizedBox(width: 12),
              Text(
                '${Formatters.numberFr(line.qty)} ticket${line.qty > 1 ? 's' : ''} disponibles',
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.08,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(height: 1, color: const Color(0xFFEAECEF)),
          const SizedBox(height: 1),
          Row(
            children: [
              Text(
                'Quantité',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              _StepperButton(
                icon: Icons.remove,
                onPressed: qty > 0 ? onDecrement : null,
                isPositive: false,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 30,
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _StepperButton(
                icon: Icons.add,
                onPressed: qty < _max ? onIncrement : null,
                isPositive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RetirerConfirmationHero extends StatelessWidget {
  const _RetirerConfirmationHero({
    required this.qrCode,
    required this.selectedTickets,
    required this.selectedAmount,
  });

  final String qrCode;
  final int selectedTickets;
  final int selectedAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.call_split_rounded,
            color: Color(0xFFB45309),
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Retrait depuis le QR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                qrCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$selectedTickets ticket${selectedTickets > 1 ? 's' : ''} · '
                '${Formatters.numberFr(selectedAmount)} MRU',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
    required this.isPositive,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: enabled
            ? (isPositive ? const Color(0xFF43A047) : const Color(0xFFF2F4F7))
            : const Color(0xFFF3F4F6),
        foregroundColor: enabled
            ? (isPositive ? Colors.white : const Color(0xFF344054))
            : const Color(0xFFB8BEC7),
        disabledBackgroundColor: const Color(0xFFF3F4F6),
        disabledForegroundColor: const Color(0xFFB8BEC7),
      ),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
