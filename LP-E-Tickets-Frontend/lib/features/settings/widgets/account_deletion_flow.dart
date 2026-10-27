import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show Bidi, DateFormat, NumberFormat;

import '../../../core/theme/app_colors.dart';
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
          child: AlertDialog(
            scrollable: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            contentPadding: const EdgeInsets.all(28),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DeletionIcon(
                  icon: Icons.check_rounded,
                  color: AppColors.success,
                  size: 72,
                ),
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await service.acknowledge();
    auth.add(const AuthAccountDeletionCompleted());
  } finally {
    timer.cancel();
  }
}

/// Resume an uncertain deletion without exposing persistence to login screens.
Future<void> recoverAccountDeletionFlow(BuildContext context) async {
  final service = ImmediateAccountDeletionService();
  try {
    if (await service.recover() && context.mounted) {
      await showDeletionSuccess(context, service);
    }
  } catch (_) {
    // Keep the receipt key for the next attempt when connectivity returns.
  }
}

Future<void> runAccountDeletionFlow(
  BuildContext context, [
  ImmediateAccountDeletionService? deletionService,
]) async {
  final service = deletionService ?? ImmediateAccountDeletionService();
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
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Center(
          child: _DeletionIcon(
            icon: Icons.person_remove_outlined,
            color: AppColors.danger,
          ),
        ),
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
      if (error is OdooJsonRpcException) {
        if (error.requiresReLogin) {
          msg = l10n.sessionExpiredReconnect;
        } else {
          msg = switch (error.normalizedPublicCode) {
            'INVALID_ACTION_CODE' ||
            'SECRET_CODE_INVALID' => l10n.commonPinIncorrect,
            'ACTION_CODE_LOCKED' ||
            'RATE_LIMITED' => l10n.commonTooManyAttempts,
            _ => l10n.deletionFailure,
          };
        }
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

  Map<String, String> _labels(AppLocalizations l10n) => {
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

  String _value(String key, Object? value, AppLocalizations l10n) {
    final states = {
      'active': l10n.deletionActive,
      'blocked': l10n.deletionBlocked,
      'consumed': l10n.deletionConsumed,
      'expired': l10n.deletionExpired,
    };
    if (value == null || value == '') return '—';
    if (key == 'state') return states[value] ?? '—';
    if (key == 'expires_at') {
      final date = DateTime.tryParse(value.toString());
      return date == null
          ? '—'
          : DateFormat.yMMMd(l10n.localeName).add_Hm().format(date);
    }
    if (value is num) {
      return NumberFormat.decimalPattern(l10n.localeName).format(value);
    }
    return value.toString();
  }

  String _reportText(AppLocalizations l10n) {
    final labels = _labels(l10n);
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
          final value = _value(entry.key, entry.value, l10n);
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
    text.writeln(l10n.deletionCopiesNotice);
    text.writeln('\n${l10n.deletionReportWarning}');
    return text.toString();
  }

  Widget _section(
    String key,
    String title,
    IconData icon,
    AppLocalizations l10n,
  ) {
    final rows = widget.report.rows(key);
    final labels = _labels(l10n);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                NumberFormat.decimalPattern(
                  l10n.localeName,
                ).format(rows.length),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              l10n.deletionEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _value('reference', row['reference'], l10n),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in row.entries)
                    if (entry.key != 'reference' &&
                        labels.containsKey(entry.key))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                labels[entry.key]!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _value(entry.key, entry.value, l10n),
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 8, 16),
      child: Row(
        children: [
          _DeletionIcon(
            icon: Icons.account_balance_wallet_outlined,
            color: scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.deletionReportTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.commonCloseTooltip,
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            'wallets',
            l10n.deletionWallets,
            Icons.account_balance_wallet_outlined,
            l10n,
          ),
          _section(
            'carnets',
            l10n.deletionCarnets,
            Icons.confirmation_number_outlined,
            l10n,
          ),
          _section('qrs', l10n.deletionQrs, Icons.qr_code_rounded, l10n),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(l10n),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.deletionSave, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 20),
          _DeletionNotice(
            icon: Icons.person_off_outlined,
            title: l10n.deletionDeletedDataTitle,
            text: l10n.deletionDeletedDataText,
          ),
          const SizedBox(height: 12),
          _DeletionNotice(
            icon: Icons.receipt_long_outlined,
            title: l10n.deletionRetainedDataTitle,
            text: l10n.deletionCopiesNotice,
          ),
          const SizedBox(height: 12),
          _DeletionNotice(
            icon: Icons.info_outline_rounded,
            text: l10n.deletionReportWarning,
            warning: true,
          ),
          if (widget.report.blocked) ...[
            const SizedBox(height: 12),
            _DeletionNotice(
              icon: Icons.pending_actions_rounded,
              text: l10n.deletionOperationPending,
              warning: true,
            ),
          ],
          if (widget.report.hasValue)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Material(
                color: scheme.error.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  activeColor: scheme.error,
                  value: _waive,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _waive = value == true),
                  title: Text(
                    l10n.deletionWaiver,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ),
        ],
      ),
    );
    final actions = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context, 'wallet'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.deletionManageWallet,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed:
                _saving ||
                    widget.report.blocked ||
                    (widget.report.hasValue && !_waive)
                ? null
                : () => Navigator.pop(context, 'delete'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.deletionConfirm, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
    final size = MediaQuery.sizeOf(context);
    final scrollAll =
        size.width < 380 ||
        size.height < 600 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * .9),
        child: scrollAll
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const Divider(height: 1),
                    content,
                    actions,
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const Divider(height: 1),
                  Flexible(child: SingleChildScrollView(child: content)),
                  actions,
                ],
              ),
      ),
    );
  }
}

class _DeletionIcon extends StatelessWidget {
  const _DeletionIcon({
    required this.icon,
    required this.color,
    this.size = 48,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, color: color, size: size * .5),
  );
}

class _DeletionNotice extends StatelessWidget {
  const _DeletionNotice({
    required this.icon,
    required this.text,
    this.title,
    this.warning = false,
  });
  final IconData icon;
  final String text;
  final String? title;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? scheme.error.withValues(alpha: .07)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: warning ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title ?? text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: title == null
                        ? FontWeight.w500
                        : FontWeight.w700,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (title != null) ...[
            const SizedBox(height: 10),
            SelectableText(
              text,
              textDirection: Bidi.detectRtlDirectionality(text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
