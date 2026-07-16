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
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import 'qr_action_confirmation_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

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
    final l10n = AppLocalizations.of(context);
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _parent = null;
        _loading = false;
        _error = l10n.qrServerRequiredForSeparation;
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
          _error = l10n.qrOnlyBlockedCanSeparate;
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final parent = _parent;
    if (parent == null || parent.state != QrState.blocked) return;
    final actionCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrActionConfirmationScreen(
          args: QrActionConfirmationArgs(
            title: l10n.qrSeparateTitle,
            subtitle: l10n.qrSeparateSubtitle,
            confirmLabel: l10n.qrSeparateTitle,
            hero: _SeparerConfirmationHero(
              qrCode: parent.publicCode,
              validCount: parent.lines
                  .where((l) => !l.isExpired)
                  .fold<int>(0, (s, l) => s + l.qty),
              expiredCount: parent.lines
                  .where((l) => l.isExpired)
                  .fold<int>(0, (s, l) => s + l.qty),
            ),
            details: _SeparerConfirmationLinesSection(lines: parent.lines),
            summaryRows: [
              QrActionSummaryRow(
                label: l10n.detail,
                value: '${parent.lines.length}',
              ),
              QrActionSummaryRow(
                label: l10n.validTickets,
                value:
                    '${parent.lines.where((l) => !l.isExpired).fold<int>(0, (s, l) => s + l.qty)}',
              ),
              QrActionSummaryRow(
                label: l10n.expiredTickets,
                value:
                    '${parent.lines.where((l) => l.isExpired).fold<int>(0, (s, l) => s + l.qty)}',
              ),
            ],
            disclaimer: l10n.qrSeparationDisclaimer,
          ),
        ),
      ),
    );

    if (actionCode != null && actionCode.isNotEmpty) {
      if (!mounted) return;
      final intent = SensitiveActionIntent.create('qr-separer');
      await _performSubmit(actionCode, intent);
    }
  }

  Future<void> _performSubmit(
    String actionCode,
    SensitiveActionIntent intent,
  ) async {
    final l10n = AppLocalizations.of(context);
    final parent = _parent;
    if (parent == null || parent.state != QrState.blocked) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) throw Exception(l10n.commonSessionRequired);

    setState(() => _submitting = true);
    try {
      final raw = await OdooFueltokenFacade().qrSeparer(
        intent.withAuthParams({
          'public_code': parent.publicCode,
        }, actionCode: actionCode),
      );
      final payload = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Séparation QR refusée par le serveur.',
        publicErrorMessage: l10n.qrSeparationFailed,
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
      AppMessage.success(context, l10n.qrSeparationSuccess);
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
                title: l10n.qrSeparateTitle,
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
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(
                  0xFFF59E0B,
                ).withValues(alpha: 0.35),
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
              label: Text(
                _submitting ? l10n.qrSeparationInProgress : l10n.qrSeparate,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: l10n.qrSeparateTitle,
              subtitle: l10n.qrSeparateSubtitle,
              onBack: () => popOrGo(context, '/qr'),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _SeparationSummaryCard(
                    qrCode: parent.publicCode,
                    createdAt: parent.createdAt,
                    validCount: validCount,
                    expiredCount: expiredCount,
                    validAmount: validAmount,
                    expiredAmount: expiredAmount,
                  ),
                  const SizedBox(height: 18),
                  SectionLabel(l10n.currentDistribution),
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(
                      children: [
                        _SummaryStatRow(
                          label: l10n.validTickets,
                          value: '$validCount',
                        ),
                        const SizedBox(height: 8),
                        _SummaryStatRow(
                          label: l10n.expiredTickets,
                          value: '$expiredCount',
                        ),
                        const SizedBox(height: 8),
                        _SummaryStatRow(
                          label: l10n.validAmount,
                          value: Formatters.money(validAmount),
                        ),
                        const SizedBox(height: 8),
                        _SummaryStatRow(
                          label: l10n.expiredAmount,
                          value: Formatters.money(expiredAmount),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SectionLabel(l10n.ticketDistribution),
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

class _SeparationSummaryCard extends StatelessWidget {
  const _SeparationSummaryCard({
    required this.qrCode,
    required this.createdAt,
    required this.validCount,
    required this.expiredCount,
    required this.validAmount,
    required this.expiredAmount,
  });

  final String qrCode;
  final DateTime createdAt;
  final int validCount;
  final int expiredCount;
  final int validAmount;
  final int expiredAmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.qrToSeparate,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              Text(
                Formatters.dateTimeDash(createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.qrValidLinesMoved,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.body,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            qrCode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryStatBlock(
                  label: l10n.validTickets,
                  value: '$validCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryStatBlock(
                  label: l10n.expiredTickets,
                  value: '$expiredCount',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryStatBlock(
                  label: l10n.validAmount,
                  value: Formatters.money(validAmount),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryStatBlock(
                  label: l10n.expiredAmount,
                  value: Formatters.money(expiredAmount),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStatBlock extends StatelessWidget {
  const _SummaryStatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStatRow extends StatelessWidget {
  const _SummaryStatRow({required this.label, required this.value});

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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _SeparerConfirmationHero extends StatelessWidget {
  const _SeparerConfirmationHero({
    required this.qrCode,
    required this.validCount,
    required this.expiredCount,
  });

  final String qrCode;
  final int validCount;
  final int expiredCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              Text(
                l10n.qrToSeparate,
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.qrValidExpiredSummary(validCount, expiredCount),
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

class _SeparerConfirmationLinesSection extends StatelessWidget {
  const _SeparerConfirmationLinesSection({required this.lines});

  final List<QrLine> lines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.qrLines,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < lines.length; i++) ...[
            _SeparerConfirmationLineRow(line: lines[i]),
            if (i < lines.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE5E7EB),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SeparerConfirmationLineRow extends StatelessWidget {
  const _SeparerConfirmationLineRow({required this.line});

  final QrLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isExpired = line.isExpired;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ticketCount(line.qty),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.ticketStatusWithDate(
                  isExpired ? l10n.statusExpired : l10n.statusActive,
                  Formatters.dateTime(line.expirationDate),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AmountInline(
          amount: line.amount,
          valueStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isExpired ? AppColors.muted : AppColors.ink,
          ),
          unitStyle: TextStyle(
            color: isExpired ? AppColors.muted : AppColors.ink,
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.ticketCount(line.qty),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.ticketStatusWithDate(
                    isExpired ? l10n.statusExpired : l10n.statusActive,
                    Formatters.dateTime(line.expirationDate),
                  ),
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
          AmountInline(
            amount: line.amount,
            valueStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isExpired ? AppColors.muted : AppColors.ink,
            ),
            unitStyle: TextStyle(
              color: isExpired ? AppColors.muted : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
