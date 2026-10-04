import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

class QrLimitDialog extends StatefulWidget {
  const QrLimitDialog({
    super.key,
    required this.currentAmount,
    required this.currency,
  });

  final int currentAmount;
  final String currency;

  @override
  State<QrLimitDialog> createState() => _QrLimitDialogState();
}

class _QrLimitDialogState extends State<QrLimitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: '${widget.currentAmount}');

  int? _parsedAmount(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'\s'), ''));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.qrLimitTitle),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.qrLimitAmountLabel(widget.currency),
            hintText: l10n.qrLimitAmountHint,
            errorMaxLines: 3,
          ),
          validator: (value) {
            final amount = _parsedAmount(value ?? '');
            if (amount == null || amount <= 0) {
              return l10n.qrLimitInvalidAmount;
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(_parsedAmount(_amount.text));
          },
          child: Text(l10n.qrLimitApply),
        ),
      ],
    );
  }
}
