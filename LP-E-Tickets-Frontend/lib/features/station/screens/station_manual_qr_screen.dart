import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/station_qr_check_result.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../../shared/widgets/station_qr_failure_dialog.dart';
import '../../../shared/widgets/station_qr_success_dialog.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Saisie station du code manuel affiché au client.
///
/// Doctrine V1 : le code manuel est un mode de saisie équivalent au scan QR.
/// Il envoie `qr_numeric_code` aux routes station, jamais un champ legacy.
class StationManualQrScreen extends StatefulWidget {
  const StationManualQrScreen({super.key});

  @override
  State<StationManualQrScreen> createState() => _StationManualQrScreenState();
}

class _StationManualQrScreenState extends State<StationManualQrScreen> {
  final TextEditingController _codeController = TextEditingController();

  bool _checking = false;
  bool _consuming = false;
  Map<String, dynamic>? _checkData;
  String? _checkedNumericCode;
  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _numericCode =>
      _codeController.text.replaceAll(RegExp(r'\D'), '').trim();

  Map<String, dynamic> _payloadFor(String code) {
    final normalized = code.replaceAll(RegExp(r'\D'), '').trim();
    return <String, dynamic>{'qr_numeric_code': normalized};
  }

  Map<String, dynamic> _dataMap(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final top = Map<String, dynamic>.from(raw);
    final data = top['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return top;
  }

  String _stringAny(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return '';
    for (final key in keys) {
      final value = map[key];
      if (value == null || value == false) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool _boolAny(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return false;
    for (final key in keys) {
      final value = map[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final text = value.trim().toLowerCase();
        if (text == 'true' || text == '1' || text == 'yes') return true;
        if (text == 'false' || text == '0' || text == 'no') return false;
      }
    }
    return false;
  }

  String _errorMessage(Object error) {
    final l10n = AppLocalizations.of(context);
    final message = ErrorPresenter.localizedMessage(context, error);
    if (message.isEmpty) return l10n.stationQrNotConsumableMessage;
    if (message.contains('debug_reason') || message.contains('Traceback')) {
      return l10n.stationQrNotConsumableMessage;
    }
    return message;
  }

  String _sensitiveActionErrorMessage(Object error) {
    if (ErrorPresenter.isBackendUnavailable(error)) {
      return AppLocalizations.of(context).stationConsumptionUnconfirmedMessage;
    }
    return _errorMessage(error);
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : AppColors.leaderGreen,
      ),
    );
  }

  Object? _payloadAny(Map<String, dynamic>? payload, List<String> keys) {
    if (payload == null) return null;
    for (final key in keys) {
      if (payload.containsKey(key)) return payload[key];
    }
    return null;
  }

  String? _payloadString(Map<String, dynamic>? payload, List<String> keys) {
    final value = _payloadAny(payload, keys);
    if (value == null || value == false) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _payloadDateTime(Map<String, dynamic>? payload, List<String> keys) {
    final value = _payloadAny(payload, keys);
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _formatManualDateTime(DateTime value) {
    return Formatters.dateTimeDash(value);
  }

  String _formatManualAmount(Object? value) {
    final notProvided = AppLocalizations.of(context).commonNotProvided;
    if (value == null || value == false) return notProvided;
    if (value is num) {
      final rounded = value.roundToDouble() == value
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
      return '$rounded MRU';
    }
    final text = value.toString().trim();
    return text.isEmpty ? notProvided : text;
  }

  void _invalidateStationConsumptionCaches(String routeId) {
    final detailParams = AcpecQrMapper.detailParamsForRouteId(routeId);
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.qrDetail,
      detailParams,
    );
    for (final params in [
      const <String, dynamic>{},
      const <String, dynamic>{'state': 'active'},
      const <String, dynamic>{'state': 'blocked'},
      const <String, dynamic>{'state': 'consumed'},
    ]) {
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
        params,
      );
    }
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.transactions,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.stationTransactions,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.walletCurrent,
      Map<String, dynamic>.from(
        OdooFueltokenRpcConfig.walletCurrentDefaultParams,
      ),
    );
  }

  Future<void> _showManualSuccessDialog({
    required String amount,
    required DateTime consumedAt,
    required String transactionName,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      builder: (ctx) {
        return StationQrSuccessDialog(
          amount: amount,
          consumedAt: _formatManualDateTime(consumedAt),
          transactionName: transactionName,
          onClose: () => Navigator.pop(ctx),
        );
      },
    );
  }

  Future<void> _showManualFailureDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      builder: (ctx) {
        return StationQrFailureDialog(
          title: title,
          message: message,
          actionLabel: actionLabel,
          onClose: () => Navigator.pop(ctx),
        );
      },
    );
  }

  Future<void> _checkManualCode() async {
    final l10n = AppLocalizations.of(context);
    final code = _numericCode;
    if (code.isEmpty) {
      _showSnack(l10n.stationEnterManualCode, error: true);
      return;
    }
    if (_checking || _consuming) return;

    setState(() {
      _checking = true;
      _checkData = null;
      _checkedNumericCode = null;
    });

    try {
      final raw = await OdooFueltokenFacade().stationQrCheck(_payloadFor(code));
      final result = StationQrCheckResult.fromRpc(raw);
      if (!mounted) return;

      if (!result.canConsume) {
        await _showManualFailureDialog(
          title: l10n.stationQrNotConsumable,
          message: l10n.stationQrNotConsumableMessage,
          actionLabel: l10n.stationBackHome,
        );
        if (mounted) context.go('/station/home');
        return;
      }

      final data = _dataMap(raw);
      data['can_consume'] = true;
      if (result.publicCode != null) {
        data.putIfAbsent('public_code', () => result.publicCode);
      }
      if (result.clientName != null) {
        data.putIfAbsent('client_name', () => result.clientName);
      }
      if (result.totalAmount != null) {
        data.putIfAbsent('amount_total', () => result.totalAmount);
      }

      setState(() {
        _checkData = data;
        _checkedNumericCode = code;
      });
    } catch (e) {
      if (!mounted) return;
      // Panne réseau/serveur : le QR n’est pas jugé. L’opérateur reste sur
      // la saisie pour réessayer sans retaper les 12 chiffres.
      final technical = ErrorPresenter.isBackendUnavailable(e);
      await _showManualFailureDialog(
        title: technical
            ? l10n.stationVerificationImpossible
            : l10n.stationQrNotConsumable,
        message: _errorMessage(e),
        actionLabel: technical ? l10n.stationBackToEntry : l10n.stationBackHome,
      );
      if (mounted && !technical) context.go('/station/home');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _consumeManualCode() async {
    final l10n = AppLocalizations.of(context);
    final code = _checkedNumericCode ?? _numericCode;
    if (code.trim().isEmpty || _checkData == null) {
      _showSnack(l10n.stationCheckCodeFirst, error: true);
      return;
    }
    if (!_boolAny(_checkData, const ['can_consume', 'canConsume'])) {
      await _showManualFailureDialog(
        title: l10n.stationQrNotConsumable,
        message: l10n.stationQrNotConsumableMessage,
        actionLabel: l10n.stationBackHome,
      );
      if (mounted) context.go('/station/home');
      return;
    }
    if (_checking || _consuming) return;
    if (!mounted) return;

    setState(() => _consuming = true);

    try {
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: l10n.stationPinVerification,
        description: l10n.stationPinManualDescription,
      );
      if (actionCode == null || actionCode.isEmpty || !mounted) return;
      final intent = SensitiveActionIntent.create('station-qr-use');
      final raw = await OdooFueltokenFacade().stationQrUse(
        intent.withAuthParams(_payloadFor(code), actionCode: actionCode),
      );
      final guarded = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: l10n.stationConsumptionRejected,
        publicErrorMessage: l10n.stationConsumptionFailed,
      );

      final amount = _formatManualAmount(
        _payloadAny(guarded, const ['amount_total', 'amountTotal']),
      );
      final transactionName =
          _payloadString(guarded, const [
            'transaction_name',
            'transactionName',
          ]) ??
          l10n.commonNotProvided;
      final consumedAt =
          _payloadDateTime(guarded, const [
            'consumed_at',
            'consumedAt',
            'transaction_created_at',
            'transactionCreatedAt',
            'created_at',
            'createdAt',
          ]) ??
          DateTime.now();
      final invalidationRouteId =
          _payloadString(guarded, const [
            'qr_public_code',
            'public_code',
            'publicCode',
          ]) ??
          _stringAny(_checkData, const [
            'qr_public_code',
            'public_code',
            'publicCode',
          ]);
      _invalidateStationConsumptionCaches(
        invalidationRouteId.isEmpty ? code : invalidationRouteId,
      );

      ClientHistoryRefreshBus.instance.bump();
      WalletRefreshBus.instance.bump();

      if (!mounted) return;
      setState(() {
        _checkData = null;
        _checkedNumericCode = null;
        _codeController.clear();
      });
      await _showManualSuccessDialog(
        amount: amount,
        consumedAt: consumedAt,
        transactionName: transactionName,
      );
      if (mounted) context.go('/station/home');
    } catch (e) {
      if (!mounted) return;
      final technical = ErrorPresenter.isBackendUnavailable(e);
      await _showManualFailureDialog(
        title: technical
            ? l10n.stationConsumptionUnconfirmed
            : l10n.stationOperationRejected,
        message: technical
            ? l10n.stationConsumptionUnconfirmedMessage
            : _sensitiveActionErrorMessage(e),
        actionLabel: l10n.stationBackToEntry,
      );
    } finally {
      if (mounted) setState(() => _consuming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final stationName = (user?.stationName?.trim().isNotEmpty == true)
        ? user!.stationName!.trim()
        : l10n.station;

    final data = _checkData;
    final canConsume = _boolAny(data, const ['can_consume', 'canConsume']);
    final owner = _stringAny(data, const [
      'client_name',
      'partner_name',
      'owner_name',
    ]);
    final amount = _stringAny(data, const ['amount_total', 'amountTotal']);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l10n.stationManualTitle),
        leading: IconButton(
          onPressed: _consuming ? null : () => context.go('/station/home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Text(
              stationName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.stationManualInstruction,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 22),
            _ManualCodeCard(
              controller: _codeController,
              checking: _checking,
              onCheck: _checkManualCode,
            ),
            const SizedBox(height: 18),
            if (data != null && canConsume)
              _CheckResultCard(
                owner: owner,
                amount: amount,
                consuming: _consuming,
                onConsume: _consumeManualCode,
              ),
          ],
        ),
      ),
    );
  }
}

class _ManualCodeCard extends StatelessWidget {
  const _ManualCodeCard({
    required this.controller,
    required this.checking,
    required this.onCheck,
  });

  final TextEditingController controller;
  final bool checking;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E6DD)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.stationManualClientCode,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: const [_ManualQrCodeInputFormatter()],
            onSubmitted: (_) => checking ? null : onCheck(),
            decoration: InputDecoration(
              hintText: l10n.stationManualExample,
              helperText: l10n.stationManualFormat,
              prefixIcon: const Icon(Icons.pin_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(checking ? l10n.stationChecking : l10n.stationCheck),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.leaderGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualQrCodeInputFormatter extends TextInputFormatter {
  const _ManualQrCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buffer = StringBuffer();

    for (var index = 0; index < limited.length; index += 1) {
      if (index > 0 && index % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(limited[index]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}

class _CheckResultCard extends StatelessWidget {
  const _CheckResultCard({
    required this.owner,
    required this.amount,
    required this.consuming,
    required this.onConsume,
  });

  final String owner;
  final String amount;
  final bool consuming;
  final VoidCallback onConsume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusText = l10n.stationConsumable;
    final statusColor = AppColors.leaderGreen;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E6DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
            label: l10n.stationClient,
            value: owner.isEmpty ? '—' : owner,
          ),
          _InfoRow(label: l10n.amount, value: amount.isEmpty ? '—' : amount),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: consuming ? null : onConsume,
              icon: consuming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_gas_station_outlined),
              label: Text(
                consuming ? l10n.stationConsuming : l10n.stationConsume,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.leaderGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E6DD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 1234-5678-9012
