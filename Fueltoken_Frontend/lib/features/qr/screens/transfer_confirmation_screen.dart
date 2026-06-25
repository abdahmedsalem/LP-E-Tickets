import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

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
  final Future<void> Function(String actionCode) onConfirm;
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
      setState(() => _confirming = true);
      await widget.args.onConfirm(actionCode);
      if (!mounted) return;
      completed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
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

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF43A047),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _confirming ? null : _onConfirm,
                      child: Center(
                        child: _confirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Confirmer l\'envoi',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: _confirming
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Confirmer l\'envoi',
              onBack: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  // â”€â”€ Hero destinataire + montant â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Text(
                    'Vérifiez les carnets avant de confirmer.',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TransferHeroCard(
                    recipientName: args.recipientName,
                    recipientPhone: args.recipientPhone,
                  ),
                  const SizedBox(height: 20),

                  // â”€â”€ Carnets transférés â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _SectionHeader(label: 'Carnets envoyés'),
                  const SizedBox(height: 8),
                  _TransferLinesList(lines: args.lines),
                  const SizedBox(height: 16),
                  _TransferSummaryAmount(lines: args.lines),

                  // â”€â”€ Note â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  if (args.note != null && args.note!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'Message'),
                    const SizedBox(height: 8),
                    _NoteCard(note: args.note!),
                  ],

                  const SizedBox(height: 24),
                  _DisclaimerText(recipientName: args.recipientName),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Sub-widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TransferHeroCard extends StatelessWidget {
  const _TransferHeroCard({
    required this.recipientName,
    required this.recipientPhone,
  });
  final String recipientName;
  final String recipientPhone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF2FBF3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFE8D1)),
      ),
      child: Column(
        children: [
          // Flèche de transfert
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_RecipientAvatar(name: recipientName)],
          ),
          const SizedBox(height: 10),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppColors.muted,
      ),
    );
  }
}

class _TransferLinesList extends StatelessWidget {
  const _TransferLinesList({required this.lines});
  final List<TransferConfirmationLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                color: AppColors.lineSoft,
                indent: 16,
                endIndent: 16,
              ),
            _TransferLineRow(line: lines[i]),
          ],
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _carnetTypeLabel(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (line.faceLine.expirationDate.year < 9999) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Expire le ${Formatters.dateTimeDash(line.faceLine.expirationDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AmountInline(
            amount: line.totalAmount,
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferSummaryAmount extends StatelessWidget {
  const _TransferSummaryAmount({required this.lines});
  final List<TransferConfirmationLine> lines;

  @override
  Widget build(BuildContext context) {
    final totalAmount = lines.fold(0, (s, l) => s + l.totalAmount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          const Text(
            'Total',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          _AmountInline(
            amount: totalAmount,
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
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

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText({required this.recipientName});
  final String recipientName;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Le transfert vers $recipientName est définitif et ne peut pas être annulé après confirmation.',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.muted,
        height: 1.45,
      ),
    );
  }
}
