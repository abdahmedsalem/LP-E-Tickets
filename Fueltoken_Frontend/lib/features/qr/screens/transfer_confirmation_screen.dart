import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../../shared/widgets/standard_confirmation_scaffold.dart';
import '../../../shared/widgets/transfer_line_row.dart';

/// Arguments passés à [TransferConfirmationScreen].
class TransferConfirmationArgs {
  const TransferConfirmationArgs({
    required this.recipientPhone,
    required this.recipientName,
    required this.lines,
    this.showQuantity = false,
    this.title = 'Confirmer l\'envoi',
    this.introText = 'Vérifiez les carnets avant de confirmer.',
    this.confirmLabel = 'Confirmer l\'envoi',
    this.confirmIcon = Icons.send_rounded,
    this.sectionLabel = 'Carnets envoyés',
    this.intentOperation = 'carnets-transfer',
    this.unconfirmedActionMessage =
        'Action non confirmée. Vérifiez l’état de l’opération avant de réessayer.',
    this.onConfirm,
  }) : assert(onConfirm != null);

  /// Numéro de téléphone du destinataire (tel que saisi).
  final String recipientPhone;

  /// Nom résolu du destinataire (retourné par le backend lors de la vérification).
  final String recipientName;

  /// Lignes de transfert sélectionnées.
  final List<TransferConfirmationLine> lines;
  final bool showQuantity;

  final String title;
  final String introText;
  final String confirmLabel;
  final IconData confirmIcon;
  final String sectionLabel;
  final String intentOperation;
  final String unconfirmedActionMessage;

  /// Callback appelé quand l'utilisateur confirme sans motif éditable.
  final Future<void> Function(String actionCode, SensitiveActionIntent intent)?
  onConfirm;

}

class TransferConfirmationLine {
  const TransferConfirmationLine({
    required this.faceLine,
    required this.carnetQty,
    required this.carnetSize,
  });

  final FaceLine faceLine;
  final int carnetQty;
  final int carnetSize;

  int get totalFaces => carnetQty * carnetSize;
  int get totalAmount => totalFaces * faceLine.faceValue;
}

// -----------------------------------------------------------------------------

class TransferConfirmationScreen extends StatefulWidget {
  const TransferConfirmationScreen({super.key, required this.args});

  final TransferConfirmationArgs args;

  @override
  State<TransferConfirmationScreen> createState() =>
      _TransferConfirmationScreenState();
}

class _TransferConfirmationScreenState
    extends State<TransferConfirmationScreen> {
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

  Future<void> _onConfirm() async {
    if (_confirming) return;
    var completed = false;
    setState(() => _confirming = true);
    try {
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: 'Vérification du PIN',
        description: 'Saisissez votre PIN pour confirmer cette opération.',
      );
      if (actionCode == null || actionCode.isEmpty || !mounted) return;
      final intent = SensitiveActionIntent.create(widget.args.intentOperation);
      await widget.args.onConfirm!(actionCode, intent);
      if (!mounted) return;
      completed = true;
      _close(true);
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        AppMessage.error(
          context,
          ErrorPresenter.isBackendUnavailable(e)
              ? widget.args.unconfirmedActionMessage
              : ErrorPresenter.message(e),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        AppMessage.error(
          context,
          ErrorPresenter.isBackendUnavailable(e)
              ? widget.args.unconfirmedActionMessage
              : ErrorPresenter.message(e),
        );
      }
      return;
    } finally {
      if (mounted && !completed) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;

    return StandardConfirmationScaffold(
      title: args.title,
      introText: args.introText,
      confirmLabel: args.confirmLabel,
      confirmIcon: args.confirmIcon,
      confirmIconSize: 17,
      topSpacing: 14,
      confirming: _confirming,
      onConfirm: _onConfirm,
      onCancel: () => _close(false),
      onBack: () => _close(false),
      content: [
        _TransferConfirmationHeroCard(
          recipientName: args.recipientName,
        ),
        const SizedBox(height: 20),
        _TransferConfirmationSectionHeader(label: args.sectionLabel),
        const SizedBox(height: 14),
        _TransferConfirmationLinesCard(
          lines: args.lines,
          showQuantity: args.showQuantity,
        ),
        const SizedBox(height: 24),
        _TransferConfirmationDisclaimerText(recipientName: args.recipientName),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

class _TransferConfirmationHeroCard extends StatelessWidget {
  const _TransferConfirmationHeroCard({
    required this.recipientName,
  });

  final String recipientName;

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
      child: Row(
        children: [
          _RecipientAvatar(name: recipientName),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destinataire',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recipientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferConfirmationSectionHeader extends StatelessWidget {
  const _TransferConfirmationSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
  }
}

class _TransferConfirmationLinesCard extends StatelessWidget {
  const _TransferConfirmationLinesCard({
    required this.lines,
    required this.showQuantity,
  });

  final List<TransferConfirmationLine> lines;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final totalAmount = lines.fold<int>(0, (s, l) => s + l.totalAmount);

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
          for (var i = 0; i < lines.length; i++) ...[
            _TransferLineRow(line: lines[i], showQuantity: showQuantity),
            if (i < lines.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
          ],
          if (lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(height: 1, color: const Color(0xFFE5E7EB)),
            ),
          _TransferTotalRow(totalAmount: totalAmount),
        ],
      ),
    );
  }
}

class _TransferTotalRow extends StatelessWidget {
  const _TransferTotalRow({required this.totalAmount});

  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Montant total',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.body,
            ),
          ),
        ),
        _AmountInline(
          amount: totalAmount,
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
        ),
      ],
    );
  }
}

class _TransferConfirmationDisclaimerText extends StatelessWidget {
  const _TransferConfirmationDisclaimerText({required this.recipientName});

  final String recipientName;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Le transfert vers $recipientName est définitif et ne peut pas être annulé après confirmation.',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12.5,
        color: AppColors.muted,
        height: 1.45,
      ),
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({required this.name});
  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TransferLineRow extends StatelessWidget {
  const _TransferLineRow({required this.line, required this.showQuantity});
  final TransferConfirmationLine line;
  final bool showQuantity;

  String _carnetTypeLabel() {
    return Formatters.carnetTypeLabelFromServer(
      line.faceLine.carnetTypeName,
      fallbackSize: line.carnetSize,
      fallbackFaceValue: line.faceLine.faceValue,
      fallbackCode: line.faceLine.carnetTypeCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TransferLineRow(
      title: _carnetTypeLabel(),
      quantity: line.carnetQty,
      amount: line.totalAmount,
      showQuantity: showQuantity,
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
