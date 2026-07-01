import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/auth_action_code_dialog.dart';
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
    return <String, dynamic>{'qr_numeric_code': code.trim()};
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
    if (error is OdooJsonRpcException) return error.message;
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return 'Le code QR ne peut pas être vérifié.';
    if (text.contains('debug_reason') || text.contains('Traceback')) {
      return 'Le code QR ne peut pas être vérifié.';
    }
    return text;
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

  Future<void> _checkManualCode() async {
    final code = _numericCode;
    if (code.isEmpty) {
      _showSnack('Saisissez le code manuel affiché au client.', error: true);
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
      if (!mounted) return;
      setState(() {
        _checkData = _dataMap(raw);
        _checkedNumericCode = code;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(_errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _consumeManualCode() async {
    final code = _checkedNumericCode ?? _numericCode;
    if (code.trim().isEmpty || _checkData == null) {
      _showSnack('Vérifiez le code manuel avant consommation.', error: true);
      return;
    }
    if (!_boolAny(_checkData, const ['can_consume', 'canConsume'])) {
      final reason = _stringAny(_checkData, const ['reason', 'message']);
      _showSnack(
        reason.isEmpty ? 'Ce code QR n’est pas consommable.' : reason,
        error: true,
      );
      return;
    }
    if (_checking || _consuming) return;

    final actionCode = await showSensitiveActionCodeDialog(
      context,
      title: 'Vérification du PIN',
      description: 'Saisissez votre PIN station pour consommer ce code QR.',
    );
    if (actionCode == null || actionCode.isEmpty || !mounted) return;

    setState(() => _consuming = true);

    try {
      final payload = <String, dynamic>{
        ..._payloadFor(code),
        'action_code': actionCode,
        'idempotency_key': const Uuid().v4(),
      };
      await OdooFueltokenFacade().stationQrUse(payload);
      ClientHistoryRefreshBus.instance.bump();
      WalletRefreshBus.instance.bump();

      if (!mounted) return;
      setState(() {
        _checkData = null;
        _checkedNumericCode = null;
        _codeController.clear();
      });
      _showSnack('QR consommé avec succès.');
      context.go('/station/journal');
    } catch (e) {
      if (!mounted) return;
      _showSnack(_errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _consuming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final stationName = (user?.stationName?.trim().isNotEmpty == true)
        ? user!.stationName!.trim()
        : 'Station';

    final data = _checkData;
    final canConsume = _boolAny(data, const ['can_consume', 'canConsume']);
    final publicCode = _stringAny(data, const [
      'public_code',
      'publicCode',
      'qr_public_code',
    ]);
    final owner = _stringAny(data, const ['partner_name', 'owner_name']);
    final state = _stringAny(data, const ['state', 'qr_state']);
    final amount = _stringAny(data, const ['amount_total', 'amountTotal']);
    final qty = _stringAny(data, const ['face_qty_total', 'qty_total']);
    final reason = _stringAny(data, const ['reason', 'message']);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Saisie code manuel'),
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
            const Text(
              'Saisissez le code numérique affiché par le client. Ce mode est équivalent au scan QR.',
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
            if (data != null)
              _CheckResultCard(
                publicCode: publicCode,
                owner: owner,
                state: state,
                amount: amount,
                qty: qty,
                reason: reason,
                canConsume: canConsume,
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
          const Text(
            'Code manuel client',
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => checking ? null : onCheck(),
            decoration: InputDecoration(
              hintText: 'Ex. 123456789012',
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
              label: Text(checking ? 'Vérification…' : 'Vérifier'),
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

class _CheckResultCard extends StatelessWidget {
  const _CheckResultCard({
    required this.publicCode,
    required this.owner,
    required this.state,
    required this.amount,
    required this.qty,
    required this.reason,
    required this.canConsume,
    required this.consuming,
    required this.onConsume,
  });

  final String publicCode;
  final String owner;
  final String state;
  final String amount;
  final String qty;
  final String reason;
  final bool canConsume;
  final bool consuming;
  final VoidCallback onConsume;

  @override
  Widget build(BuildContext context) {
    final statusText = canConsume ? 'Consommable' : 'Non consommable';
    final statusColor = canConsume
        ? AppColors.leaderGreen
        : Colors.red.shade700;

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
          _InfoRow(label: 'QR', value: publicCode.isEmpty ? '—' : publicCode),
          _InfoRow(label: 'Client', value: owner.isEmpty ? '—' : owner),
          _InfoRow(label: 'État', value: state.isEmpty ? '—' : state),
          _InfoRow(label: 'Montant', value: amount.isEmpty ? '—' : amount),
          _InfoRow(label: 'Tickets', value: qty.isEmpty ? '—' : qty),
          if (reason.isNotEmpty) _InfoRow(label: 'Motif', value: reason),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: canConsume && !consuming ? onConsume : null,
              icon: consuming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_gas_station_outlined),
              label: Text(consuming ? 'Consommation…' : 'Consommer'),
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
