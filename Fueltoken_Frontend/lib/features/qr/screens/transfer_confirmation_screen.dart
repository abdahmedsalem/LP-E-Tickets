import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';
import '../../../shared/widgets/standard_confirmation_scaffold.dart';

/// Arguments passés à [TransferConfirmationScreen].
class TransferConfirmationArgs {
  const TransferConfirmationArgs({
    required this.recipientPhone,
    required this.recipientName,
    required this.lines,
    this.note,
    required this.onConfirm,
  });

  /// Numéro de téléphone du destinataire (tel que saisi).
  final String recipientPhone;

  /// Nom résolu du destinataire (retourné par le backend lors de la vérification).
  final String recipientName;

  /// Lignes de transfert sélectionnées.
  final List<TransferConfirmationLine> lines;

  /// Note optionnelle.
  final String? note;

  /// Callback appelé quand l'utilisateur confirme.
  final Future<void> Function(String actionCode, SensitiveActionIntent intent)
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
    try {
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: 'Vérification du PIN',
        description: 'Saisissez votre PIN pour confirmer cette opération.',
      );
      if (actionCode == null || actionCode.isEmpty || !mounted) return;
      final intent = SensitiveActionIntent.create('carnets-transfer');
      setState(() => _confirming = true);
      await widget.args.onConfirm(actionCode, intent);
      if (!mounted) return;
      completed = true;
      _close(true);
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        AppMessage.error(
          context,
          e.isOdooSessionExpired || e.isAuthRequired
              ? 'Session expirée. Reconnectez-vous.'
              : e.message,
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        AppMessage.error(
          context,
          e.toString().replaceFirst('Exception: ', '').trim(),
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
      title: 'Confirmer l\'envoi',
      introText: 'Vérifiez les carnets avant de confirmer.',
      confirmLabel: 'Confirmer l\'envoi',
      confirmIcon: Icons.send_rounded,
      confirmIconSize: 17,
      topSpacing: 14,
      confirming: _confirming,
      onConfirm: _onConfirm,
      onCancel: () => _close(false),
      onBack: () => _close(false),
      content: [
        _TransferConfirmationHeroCard(
          recipientName: args.recipientName,
          recipientPhone: args.recipientPhone,
        ),
        const SizedBox(height: 20),
        const _TransferConfirmationSectionHeader(label: 'Carnets envoyés'),
        const SizedBox(height: 14),
        _TransferConfirmationLinesCard(lines: args.lines),
        if (args.note != null && args.note!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _TransferConfirmationSectionHeader(label: 'Message'),
          const SizedBox(height: 8),
          _TransferConfirmationNoteCard(note: args.note!),
        ],
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
    required this.recipientPhone,
  });

  final String recipientName;
  final String recipientPhone;

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
                  style: GoogleFonts.poppins(
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
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recipientPhone,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
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
      style: GoogleFonts.poppins(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
  }
}

class _TransferConfirmationLinesCard extends StatelessWidget {
  const _TransferConfirmationLinesCard({required this.lines});

  final List<TransferConfirmationLine> lines;

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
            _TransferLineRow(line: lines[i]),
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
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.body,
            ),
          ),
        ),
        _AmountInline(
          amount: totalAmount,
          textAlign: TextAlign.right,
          valueStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E7D32),
          ),
          unitStyle: GoogleFonts.poppins(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}

class _TransferConfirmationNoteCard extends StatelessWidget {
  const _TransferConfirmationNoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        note,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.body,
          height: 1.45,
        ),
      ),
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
          style: GoogleFonts.poppins(
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
  const _TransferLineRow({required this.line});
  final TransferConfirmationLine line;

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
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Text(
            _carnetTypeLabel(),
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            Formatters.numberFr(line.carnetQty),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: _AmountInline(
            amount: line.totalAmount,
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
            ),
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
