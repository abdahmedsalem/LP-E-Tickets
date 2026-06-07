import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/acpec_purchase_create_result.dart';
import '../../features/purchases/screens/purchase_confirmation_screen.dart';
import '../../features/qr/screens/transfer_confirmation_screen.dart';

Future<void> showPurchaseSubmitSuccessDialog(
  BuildContext context, {
  required AcpecPurchaseCreateResult result,
  required DateTime confirmedAt,
  List<PurchaseConfirmationLine> lines = const [],
  VoidCallback? onHome,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PurchaseSubmitSuccessScreen(
        result: result,
        confirmedAt: confirmedAt,
        lines: lines,
        onHome: onHome,
      ),
    ),
  );
}

Future<void> showTransferSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  required String recipientName,
  List<TransferConfirmationLine> lines = const [],
  VoidCallback? onHome,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TransferSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        recipientName: recipientName,
        lines: lines,
        onHome: onHome,
      ),
    ),
  );
}

Future<void> showQrGenerationSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required int totalQty,
  required DateTime confirmedAt,
  List<QrGenerationSuccessLine> lines = const [],
  VoidCallback? onHome,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => QrGenerationSuccessScreen(
        totalAmount: totalAmount,
        totalQty: totalQty,
        confirmedAt: confirmedAt,
        lines: lines,
        onHome: onHome,
      ),
    ),
  );
}

class QrGenerationSuccessLine {
  const QrGenerationSuccessLine({
    required this.label,
    required this.qty,
    required this.faceValue,
    required this.expirationDate,
  });

  final String label;
  final int qty;
  final int faceValue;
  final DateTime expirationDate;

  int get totalAmount => qty * faceValue;
}

class PurchaseSubmitSuccessScreen extends StatelessWidget {
  const PurchaseSubmitSuccessScreen({
    super.key,
    required this.result,
    required this.confirmedAt,
    this.lines = const [],
    this.onHome,
  });

  final AcpecPurchaseCreateResult result;
  final DateTime confirmedAt;
  final List<PurchaseConfirmationLine> lines;
  final VoidCallback? onHome;

  int get _totalAmount => lines.fold(0, (s, l) => s + l.totalAmount);

  @override
  Widget build(BuildContext context) {
    return _SuccessScaffold(
      title: 'Commande enregistrée',
      message: 'Votre commande est en attente de validation.',
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _PurchasedLinesSection(lines: lines),
      rows: [
        _SuccessRowData(
          label: 'Montant total',
          value: Formatters.money(_totalAmount),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTime(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
      onHome: onHome,
    );
  }
}

class TransferSuccessScreen extends StatelessWidget {
  const TransferSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.confirmedAt,
    required this.recipientName,
    this.lines = const [],
    this.onHome,
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String recipientName;
  final List<TransferConfirmationLine> lines;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return _SuccessScaffold(
      title: 'Transfert confirmé',
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _TransferredLinesSection(lines: lines),
      rows: [
        _SuccessRowData(
          label: 'Client receveur',
          value: recipientName,
          valueColor: AppColors.ink,
        ),
        _SuccessRowData(
          label: 'Montant total',
          value: Formatters.money(totalAmount),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTime(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
      onHome: onHome,
    );
  }
}

class QrGenerationSuccessScreen extends StatelessWidget {
  const QrGenerationSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.totalQty,
    required this.confirmedAt,
    this.lines = const [],
    this.onHome,
  });

  final int totalAmount;
  final int totalQty;
  final DateTime confirmedAt;
  final List<QrGenerationSuccessLine> lines;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return _SuccessScaffold(
      title: 'QR généré',
      message: 'Votre QR est disponible dans la liste des QR.',
      icon: Icons.qr_code_2_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _GeneratedQrLinesSection(lines: lines),
      rows: [
        _SuccessRowData(
          label: 'Montant total',
          value: Formatters.money(totalAmount),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Tickets',
          value: Formatters.numberFr(totalQty),
          valueColor: AppColors.ink,
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTime(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
      onHome: onHome,
    );
  }
}

class _SuccessScaffold extends StatelessWidget {
  const _SuccessScaffold({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.rows,
    this.details,
    this.message,
    this.onHome,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Color accentColor;
  final List<_SuccessRowData> rows;
  final Widget? details;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAF8EC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: accentColor, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (details != null) ...[
                      details!,
                      const SizedBox(height: 18),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            _SummaryRow(
                              label: rows[i].label,
                              value: rows[i].value,
                              valueColor: rows[i].valueColor,
                            ),
                            if (i < rows.length - 1) const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: onHome ?? () => context.go('/home'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Retour à l'accueil",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchasedLinesSection extends StatelessWidget {
  const _PurchasedLinesSection({required this.lines});

  final List<PurchaseConfirmationLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Carnets achetés',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < lines.length; i++) ...[
            _PurchasedLineRow(line: lines[i]),
            if (i < lines.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: const Color(0xFFE5E7EB),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferredLinesSection extends StatelessWidget {
  const _TransferredLinesSection({required this.lines});

  final List<TransferConfirmationLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Carnets transférés',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < lines.length; i++) ...[
            _TransferredLineRow(line: lines[i]),
            if (i < lines.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: const Color(0xFFE5E7EB),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferredLineRow extends StatelessWidget {
  const _TransferredLineRow({required this.line});

  final TransferConfirmationLine line;

  String _carnetTypeLabel() {
    final size = line.carnetSize;
    final faceValue = line.faceLine.faceValue;
    if (size > 0 && faceValue > 0) {
      return Formatters.carnetTypeLabel(size, faceValue);
    }
    return Formatters.normalizeCarnetTypeLabel(
      line.faceLine.carnetTypeName,
      fallbackSize: size,
      fallbackFaceValue: faceValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            _carnetTypeLabel(),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          Formatters.money(line.totalAmount),
          textAlign: TextAlign.right,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _GeneratedQrLinesSection extends StatelessWidget {
  const _GeneratedQrLinesSection({required this.lines});

  final List<QrGenerationSuccessLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Carnets utilisés',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < lines.length; i++) ...[
            _GeneratedQrLineRow(line: lines[i]),
            if (i < lines.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE5E7EB),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GeneratedQrLineRow extends StatelessWidget {
  const _GeneratedQrLineRow({required this.line});

  final QrGenerationSuccessLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Expire le ${Formatters.date(line.expirationDate)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${Formatters.numberFr(line.qty)} tickets',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.body,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              Formatters.money(line.totalAmount),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2B8F3A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PurchasedLineRow extends StatelessWidget {
  const _PurchasedLineRow({required this.line});

  final PurchaseConfirmationLine line;

  String _carnetTypeLabel() {
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
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            _carnetTypeLabel(),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            '${Formatters.numberFr(line.qty)} carnets',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            Formatters.money(line.totalAmount),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2B8F3A),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessRowData {
  const _SuccessRowData({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;
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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
