import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../../shared/widgets/standard_confirmation_scaffold.dart';

class QrActionConfirmationArgs {
  const QrActionConfirmationArgs({
    required this.title,
    required this.confirmLabel,
    required this.hero,
    required this.summaryRows,
    this.subtitle,
    this.details,
    this.disclaimer,
    this.showHero = true,
  });

  final String title;
  final String confirmLabel;
  final String? subtitle;
  final Widget hero;
  final Widget? details;
  final List<QrActionSummaryRow> summaryRows;
  final String? disclaimer;
  final bool showHero;
}

class QrActionSummaryRow {
  const QrActionSummaryRow({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;
}

class QrActionConfirmationScreen extends StatefulWidget {
  const QrActionConfirmationScreen({super.key, required this.args});

  final QrActionConfirmationArgs args;

  @override
  State<QrActionConfirmationScreen> createState() =>
      _QrActionConfirmationScreenState();
}

class _QrActionConfirmationScreenState
    extends State<QrActionConfirmationScreen> {
  bool _confirming = false;
  bool _closing = false;

  void _close(Object? result) {
    if (!mounted || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    try {
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: 'Vérification du PIN',
        description: 'Saisissez votre PIN pour confirmer cette opération.',
      );
      if (actionCode == null || actionCode.isEmpty || !mounted) return;
      setState(() => _confirming = true);
      _close(actionCode);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;

    return StandardConfirmationScaffold(
      title: args.title,
      introText: args.subtitle ?? 'Vérifiez les éléments avant de confirmer.',
      confirmLabel: args.confirmLabel,
      confirmIcon: Icons.qr_code_rounded,
      confirming: _confirming,
      onConfirm: _confirm,
      onCancel: () => _close(null),
      onBack: () => _close(null),
      content: [
        if (args.showHero) ...[
          _ConfirmationSectionCard(child: args.hero),
          const SizedBox(height: 20),
        ],
        if (args.details != null) ...[
          args.details!,
          const SizedBox(height: 20),
        ],
        if (args.summaryRows.isNotEmpty) ...[
          _SummaryRowsCard(rows: args.summaryRows),
        ],
        if (args.disclaimer != null) ...[
          const SizedBox(height: 18),
          Text(
            args.disclaimer!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmationSectionCard extends StatelessWidget {
  const _ConfirmationSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _SummaryRowsCard extends StatelessWidget {
  const _SummaryRowsCard({required this.rows});

  final List<QrActionSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _SummaryRow(
              label: rows[i].label,
              value: rows[i].value,
              valueColor: rows[i].valueColor,
            ),
            if (i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  bool _looksLikeAmount(String text) =>
      RegExp(r'^\s*[\d\s.,]+(?:\s*[A-Z]{3})?\s*$').hasMatch(text);

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
        if (_looksLikeAmount(value))
          _AmountInline(
            amount: int.parse(value.replaceAll(RegExp(r'[^0-9]'), '').trim()),
            textAlign: TextAlign.right,
            valueStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
      ],
    );
  }
}

class _AmountInline extends StatelessWidget {
  const _AmountInline({
    required this.amount,
    required this.valueStyle,
    required this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
          TextSpan(text: ' ${Formatters.defaultCurrency}', style: unitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
