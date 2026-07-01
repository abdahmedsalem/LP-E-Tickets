import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/acpec_purchase_create_result.dart';
import '../../features/purchases/screens/purchase_confirmation_screen.dart';
import '../../features/qr/screens/transfer_confirmation_screen.dart';
import 'amount_inline.dart';

Future<void> showPurchaseSubmitSuccessDialog(
  BuildContext context, {
  required AcpecPurchaseCreateResult result,
  required DateTime confirmedAt,
  List<PurchaseConfirmationLine> lines = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => PurchaseSubmitSuccessScreen(
        result: result,
        confirmedAt: confirmedAt,
        lines: lines,
      ),
    ),
  );
}

Future<void> showTransferSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  required String recipientName,
  required String recipientPhone,
  List<TransferConfirmationLine> lines = const [],
  String linesTitle = 'Carnets transférés',
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => TransferSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        lines: lines,
        linesTitle: linesTitle,
      ),
    ),
  );
}

Future<void> showQrGenerationSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  List<QrGenerationSuccessLine> lines = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => QrGenerationSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        lines: lines,
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
  });

  final AcpecPurchaseCreateResult result;
  final DateTime confirmedAt;
  final List<PurchaseConfirmationLine> lines;

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
          value: _totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTimeDash(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
    );
  }
}

class TransferSuccessScreen extends StatelessWidget {
  const TransferSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.confirmedAt,
    required this.recipientName,
    required this.recipientPhone,
    this.lines = const [],
    this.linesTitle = 'Carnets transférés',
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String recipientName;
  final String recipientPhone;
  final List<TransferConfirmationLine> lines;
  final String linesTitle;

  @override
  Widget build(BuildContext context) {
    return _SuccessScaffold(
      title: 'Transfert confirmé',
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty
          ? null
          : _TransferredLinesSection(lines: lines, title: linesTitle),
      rows: [
        _SuccessRowData(
          label: 'Client receveur',
          value: recipientName,
          valueColor: AppColors.ink,
        ),
        _SuccessRowData(
          label: 'Téléphone receveur',
          value: recipientPhone,
          valueColor: AppColors.ink,
        ),
        _SuccessRowData(
          label: 'Montant total',
          value: totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTimeDash(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
    );
  }
}

class QrGenerationSuccessScreen extends StatelessWidget {
  const QrGenerationSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.confirmedAt,
    this.lines = const [],
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final List<QrGenerationSuccessLine> lines;

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
          value: totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: 'Date',
          value: Formatters.dateTimeDash(confirmedAt),
          valueColor: AppColors.ink,
        ),
      ],
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
  });

  final String title;
  final String? message;
  final IconData icon;
  final Color accentColor;
  final List<_SuccessRowData> rows;
  final Widget? details;

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
                      style: TextStyle(
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
                        style: TextStyle(
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
                  onPressed: () => Navigator.of(context).pop(true),
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
            style: TextStyle(
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
  const _TransferredLinesSection({required this.lines, required this.title});

  final List<TransferConfirmationLine> lines;
  final String title;

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
            title,
            style: TextStyle(
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        AmountInline(amount: line.totalAmount, textAlign: TextAlign.right),
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
            style: TextStyle(
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

  String _carnetLabel() {
    final raw = line.label.trim();
    if (raw.isEmpty) return 'Carnet';
    return raw.replaceFirst(RegExp(r'^Carnet\s+', caseSensitive: false), '');
  }

  String _title() {
    final qtyLabel =
        '${Formatters.numberFr(line.qty)} ticket${line.qty > 1 ? 's' : ''}';
    return '$qtyLabel de carnet ${_carnetLabel()}';
  }

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
                _title(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Expire le ${Formatters.dateTimeDash(line.expirationDate)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        AmountInline(amount: line.totalAmount),
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
            style: TextStyle(
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: AmountInline(
            amount: line.totalAmount,
            textAlign: TextAlign.right,
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

  bool _isNumericAmount(String text) => RegExp(r'^\d+$').hasMatch(text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _isNumericAmount(value)
              ? AmountInline(
                  amount: int.parse(value),
                  textAlign: TextAlign.right,
                )
              : Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
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
