import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/immediate_account_deletion_service.dart';
import '../../../data/services/shared_services/odoo_jsonrpc_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../auth/bloc/auth_bloc.dart';

class AccountDeletionButton extends StatefulWidget {
  const AccountDeletionButton({super.key});
  @override
  State<AccountDeletionButton> createState() => _AccountDeletionButtonState();
}

class _AccountDeletionButtonState extends State<AccountDeletionButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await runAccountDeletionFlow(
                context,
                ImmediateAccountDeletionService(),
              );
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    child: Text(AppLocalizations.of(context).settingsDeleteAccount),
  );
}

Future<void> showDeletionSuccess(
  BuildContext context,
  ImmediateAccountDeletionService service,
) async {
  final auth = context.read<AuthBloc>();
  final message = AppLocalizations.of(context).deletionSuccess;
  await service.clearLocalSession();
  if (!context.mounted) return;
  BuildContext? popupContext;
  final timer = Timer(const Duration(seconds: 2), () {
    final popup = popupContext;
    if (popup != null && popup.mounted) Navigator.of(popup).pop();
  });
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        popupContext = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(content: Text(message)),
        );
      },
    );
    await service.acknowledge();
    auth.add(const AuthAccountDeletionCompleted());
  } finally {
    timer.cancel();
  }
}

Future<void> runAccountDeletionFlow(
  BuildContext context,
  ImmediateAccountDeletionService service,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    if (await service.recover()) {
      if (context.mounted) await showDeletionSuccess(context, service);
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteAccount),
        content: Text(l10n.deletionIntro),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.authContinue),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final report = await service.preview();
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeletionReportDialog(report: report),
    );
    if (!context.mounted) return;
    if (choice == 'wallet') {
      context.go('/wallet');
      return;
    }
    if (choice != 'delete') return;
    final pin = await showSensitiveActionCodeDialog(
      context,
      title: l10n.commonPinVerification,
      description: l10n.deletionPin,
    );
    if (pin == null || !context.mounted) return;
    await service.execute(
      pin: pin,
      report: report,
      waiveValue: report.hasValue,
    );
    if (context.mounted) await showDeletionSuccess(context, service);
  } catch (error) {
    if (context.mounted) {
      String msg = l10n.deletionFailure;
      if (error is OdooJsonRpcException && error.message.trim().isNotEmpty) {
        msg = error.message.trim();
      } else if (error is FormatException && error.message.trim().isNotEmpty) {
        msg = error.message.trim();
      } else if (error is StateError && error.message.trim().isNotEmpty) {
        msg = error.message.trim();
      }
      AppMessage.error(context, msg);
    }
  }
}

class _DeletionReportDialog extends StatefulWidget {
  const _DeletionReportDialog({required this.report});
  final DeletionWalletReport report;
  @override
  State<_DeletionReportDialog> createState() => _DeletionReportDialogState();
}

class _DeletionReportDialogState extends State<_DeletionReportDialog> {
  bool _waive = false;
  bool _saving = false;

  String _reportText(AppLocalizations l10n) {
    final labels = {
      'reference': l10n.deletionReference,
      'currency': l10n.deletionCurrency,
      'balance': l10n.deletionBalance,
      'available_tickets': l10n.deletionAvailable,
      'value': l10n.deletionFaceValue,
      'available': l10n.deletionAvailable,
      'qr_active': l10n.deletionActiveQr,
      'qr_blocked': l10n.deletionBlockedQr,
      'consumed': l10n.deletionConsumed,
      'expired': l10n.deletionExpired,
      'transferred': l10n.deletionTransferred,
      'expires_at': l10n.deletionExpiry,
      'state': l10n.deletionState,
      'tickets': l10n.deletionTickets,
    };
    final states = {
      'active': l10n.deletionActive,
      'blocked': l10n.deletionBlocked,
      'consumed': l10n.deletionConsumed,
      'expired': l10n.deletionExpired,
    };
    final text = StringBuffer('${l10n.deletionReportTitle}\n\n');
    for (final section in {
      'wallets': l10n.deletionWallets,
      'carnets': l10n.deletionCarnets,
      'qrs': l10n.deletionQrs,
    }.entries) {
      text.writeln(section.value);
      final rows = widget.report.rows(section.key);
      if (rows.isEmpty) text.writeln(l10n.deletionEmpty);
      for (final row in rows) {
        for (final entry in row.entries) {
          final label = labels[entry.key];
          if (label == null) continue;
          var value = entry.value?.toString() ?? '—';
          if (entry.key == 'state') value = states[value] ?? '—';
          text.writeln('$label : $value');
        }
        text.writeln();
      }
      text.writeln();
    }
    text.writeln(l10n.deletionDeletedDataTitle);
    text.writeln(l10n.deletionDeletedDataText);
    text.writeln();
    text.writeln(l10n.deletionRetainedDataTitle);
    text.writeln(widget.report.retentionNotice);
    text.writeln();
    text.writeln(l10n.deletionCopiesNotice);
    text.writeln('\n${l10n.deletionReportWarning}');
    return text.toString();
  }

  Future<void> _save(AppLocalizations l10n) async {
    setState(() => _saving = true);
    try {
      final path = await FilePicker.saveFile(
        fileName: 'LP-E-Tickets-portefeuille.txt',
        bytes: Uint8List.fromList(utf8.encode(_reportText(l10n))),
      );
      if (mounted && path != null) {
        AppMessage.success(context, l10n.deletionSaved);
      }
    } catch (_) {
      if (mounted) AppMessage.error(context, l10n.deletionSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.deletionReportTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(_reportText(l10n)),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _save(l10n),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.deletionSave),
              ),
              if (widget.report.blocked) Text(l10n.deletionOperationPending),
              if (widget.report.hasValue)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _waive,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _waive = value == true),
                  title: Text(l10n.deletionWaiver),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, 'wallet'),
          child: Text(l10n.deletionManageWallet),
        ),
        FilledButton(
          onPressed:
              _saving ||
                  widget.report.blocked ||
                  (widget.report.hasValue && !_waive)
              ? null
              : () => Navigator.pop(context, 'delete'),
          child: Text(l10n.deletionConfirm),
        ),
      ],
    );
  }
}
