import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

const _purchaseConfirmationHeaderPadding = EdgeInsets.fromLTRB(12, 8, 12, 0);
const _purchaseConfirmationHeaderGap = 10.0;
const _purchaseConfirmationHeaderTitleSize = 26.0;

class PurchaseConfirmationArgs {
  const PurchaseConfirmationArgs({
    required this.lines,
    required this.proofPath,
    this.proofBytes,
    required this.onConfirm,
  });

  final List<PurchaseConfirmationLine> lines;
  final String? proofPath;
  final Uint8List? proofBytes;
  final Future<void> Function() onConfirm;
}

class PurchaseConfirmationLine {
  const PurchaseConfirmationLine({required this.carnetType, required this.qty});

  final CarnetType carnetType;
  final int qty;

  int get totalFaces => qty * carnetType.size;
  int get totalAmount => totalFaces * carnetType.faceValue;
}

class PurchaseConfirmationScreen extends StatefulWidget {
  const PurchaseConfirmationScreen({super.key, required this.args});

  final PurchaseConfirmationArgs args;

  @override
  State<PurchaseConfirmationScreen> createState() =>
      _PurchaseConfirmationScreenState();
}

class _PurchaseConfirmationScreenState
    extends State<PurchaseConfirmationScreen> {
  bool _confirming = false;

  Future<void> _onConfirm() async {
    var completed = false;
    bool confirmed;
    try {
      confirmed = await showSensitiveActionPasswordDialog(
        context,
        title: "Confirmer l'achat",
        description: 'Saisissez votre mot de passe pour valider cet achat.',
      );
    } catch (e) {
      return;
    }

    if (!confirmed) return;

    setState(() => _confirming = true);
    try {
      await widget.args.onConfirm();
      if (mounted) {
        completed = true;
        Navigator.of(context).pop(true);
      }
    } on OdooJsonRpcException {
      return;
    } catch (e) {
      return;
    } finally {
      if (mounted && !completed) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.args.lines;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _confirming ? null : _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF43A047,
                    ).withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: _confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                            SizedBox(width: 10),
                            Text(
                              "Confirmer l'achat",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(
                      fontSize: 15,
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
            AppBarHeader(
              title: "Confirmer l'achat",
              onBack: () => Navigator.of(context).pop(false),
              largeTitle: true,
              largeTitlePadding: _purchaseConfirmationHeaderPadding,
              largeTitleGap: _purchaseConfirmationHeaderGap,
              largeTitleFontSize: _purchaseConfirmationHeaderTitleSize,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const SizedBox(height: 4),
                  const _SectionHeader(title: 'Carnets achetés'),
                  const SizedBox(height: 14),
                  _PurchaseLinesCard(lines: lines),
                  const SizedBox(height: 22),
                  const _SectionHeader(title: 'Preuve de paiement'),
                  const SizedBox(height: 14),
                  _PaymentProofImageCard(
                    proofPath: widget.args.proofPath,
                    proofBytes: widget.args.proofBytes,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "En confirmant, votre demande d'achat sera envoyée à un administrateur pour validation. "
                    'Les carnets seront crédités après approbation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
  }
}

class _PurchaseLinesCard extends StatelessWidget {
  const _PurchaseLinesCard({required this.lines});

  final List<PurchaseConfirmationLine> lines;

  String _carnetTypeLabel(PurchaseConfirmationLine line) {
    if (line.carnetType.size > 0 && line.carnetType.faceValue > 0) {
      return Formatters.carnetTypeLabel(
        line.carnetType.size,
        line.carnetType.faceValue,
      );
    }
    return Formatters.normalizeCarnetTypeLabel(
      line.carnetType.name,
      fallbackSize: line.carnetType.size,
      fallbackFaceValue: line.carnetType.faceValue,
    );
  }

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
          for (var i = 0; i < lines.length; i++) ...[
            _PurchaseLineRow(
              label: _carnetTypeLabel(lines[i]),
              qty: lines[i].qty,
              amount: lines[i].totalAmount,
            ),
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
          _TotalRow(
            totalAmount: lines.fold(0, (s, line) => s + line.totalAmount),
          ),
        ],
      ),
    );
  }
}

class _PurchaseLineRow extends StatelessWidget {
  const _PurchaseLineRow({
    required this.label,
    required this.qty,
    required this.amount,
  });

  final String label;
  final int qty;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Text(
            label,
            style: GoogleFonts.inter(
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
            Formatters.numberFr(qty),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
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
            amount: amount,
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
            unitStyle: GoogleFonts.inter(
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

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.totalAmount});

  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Montant total',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.body,
            ),
          ),
        ),
        _AmountInline(
          amount: totalAmount,
          valueStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E7D32),
          ),
          unitStyle: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
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
          TextSpan(text: ' MRU', style: unitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// Ignoré: ancien rendu conservé temporairement pour éviter une grosse diff.
// ignore: unused_element
class _PaymentProofSummaryCard extends StatelessWidget {
  const _PaymentProofSummaryCard({required this.totalAmount});

  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Montant total',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.body,
                    ),
                  ),
                ),
                Text(
                  Formatters.money(totalAmount),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'La génération créera un QR à partir des carnets sélectionnés.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentProofImageCard extends StatelessWidget {
  const _PaymentProofImageCard({required this.proofPath, this.proofBytes});

  final String? proofPath;
  final Uint8List? proofBytes;

  @override
  Widget build(BuildContext context) {
    final hasBytes = proofBytes != null && proofBytes!.isNotEmpty;
    final path = proofPath?.trim();
    final file = (path != null && path.isNotEmpty) ? File(path) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          height: 140,
          child: ColoredBox(
            color: const Color(0xFFF3F4F6),
            child: hasBytes
                ? Image.memory(
                    proofBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _missingProof(),
                  )
                : file != null
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _missingProof(),
                  )
                : _missingProof(),
          ),
        ),
      ),
    );
  }

  Widget _missingProof() {
    return Container(
      color: const Color(0xFFF8FAFC),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 34,
        color: AppColors.muted,
      ),
    );
  }
}
