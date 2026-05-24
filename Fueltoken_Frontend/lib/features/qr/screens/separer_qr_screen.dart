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

class SeparerQrScreen extends StatefulWidget {
  const SeparerQrScreen({super.key, required this.qrId});

  final String qrId;

  @override
  State<SeparerQrScreen> createState() => _SeparerQrScreenState();
}

class _SeparerQrScreenState extends State<SeparerQrScreen> {
  QrToken? _parent;
  bool _loading = false;
  bool _submitting = false;
  String? _error;

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
        _error = 'Connexion serveur ACPEC requise pour séparer un QR.';
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
      if (qr.state != QrState.blocked) {
        setState(() {
          _parent = qr;
          _loading = false;
          _error = 'Seuls les QR bloqués peuvent être séparés.';
        });
        return;
      }
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

  Future<void> _submit() async {
    final parent = _parent;
    if (parent == null || parent.state != QrState.blocked) return;

    setState(() => _submitting = true);
    try {
      final raw = await OdooFueltokenFacade().qrSeparer({
        'public_code': parent.publicCode,
        'idempotency_key': 'ft-qr-separer-${const Uuid().v4()}',
      });
      if (raw is! Map) {
        throw Exception('Réponse QR invalide.');
      }
      final newQrRaw = raw['new_qr'];
      final sourceRaw = raw['source'];
      if (newQrRaw is! Map || sourceRaw is! Map) {
        throw Exception('Réponse QR incomplète.');
      }

      final user = context.read<AuthBloc>().state.user;
      if (user == null) throw Exception('Session requise.');
      final companyId = AppEnvironment.companyIdForUser(user);
      final child = AcpecQrMapper.fromRpcEnvelope(
        newQrRaw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: companyId,
      );
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        AcpecQrMapper.detailParamsForRouteId(parent.publicCode),
      );
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        AcpecQrMapper.detailParamsForRouteId(child.publicCode),
      );
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
      );
      if (!mounted) return;
      context.pop(child.publicCode);
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.isOdooSessionExpired
                ? 'Session expirée. Reconnectez-vous.'
                : e.message,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
              AppBarHeader(title: 'Séparer le QR', onBack: () => context.pop()),
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

    final validCount = parent.lines
        .where((l) => !l.isExpired)
        .fold<int>(0, (s, l) => s + l.qty);
    final expiredCount = parent.lines
        .where((l) => l.isExpired)
        .fold<int>(0, (s, l) => s + l.qty);
    final validAmount = parent.lines
        .where((l) => !l.isExpired)
        .fold<int>(0, (s, l) => s + l.amount);
    final expiredAmount = parent.lines
        .where((l) => l.isExpired)
        .fold<int>(0, (s, l) => s + l.amount);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split_rounded, size: 18),
              label: Text(_submitting ? 'Séparation...' : 'Séparer'),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: 'Séparer le QR',
              onBack: () => context.pop(),
              action: IconBtn(
                icon: Icons.refresh_rounded,
                onPressed: _loadParent,
              ),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppPill(
                              label: 'Bloqué',
                              tone: PillTone.amber,
                              dot: true,
                            ),
                            const Spacer(),
                            Text(
                              Formatters.dateTime(parent.createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          parent.publicCode,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Les lignes non expirées seront déplacées dans un nouveau QR, sans sélection manuelle.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.body,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Répartition actuelle'),
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(
                      children: [
                        _StatRow(
                          label: 'Tickets valides',
                          value: '$validCount',
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          label: 'Tickets expirés',
                          value: '$expiredCount',
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          label: 'Montant valide',
                          value: '${Formatters.numberFr(validAmount)} MRU',
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          label: 'Montant expiré',
                          value: '${Formatters.numberFr(expiredAmount)} MRU',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Lignes'),
                  const SizedBox(height: 8),
                  for (final line in parent.lines) ...[
                    _LineCard(line: line),
                    const SizedBox(height: 10),
                  ],
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.body,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line});

  final QrLine line;

  @override
  Widget build(BuildContext context) {
    final isExpired = line.isExpired;
    return AppCard(
      child: Row(
        children: [
          FaceValueChip(value: line.faceValue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Formatters.numberFr(line.qty)} ticket${line.qty > 1 ? 's' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isExpired ? 'Expirée' : 'Active'} · ${Formatters.dateTime(line.expirationDate)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${Formatters.numberFr(line.amount)} MRU',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isExpired ? AppColors.muted : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
