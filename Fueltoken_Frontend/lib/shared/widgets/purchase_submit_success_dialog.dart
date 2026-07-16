import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/acpec_purchase_create_result.dart';
import '../../features/purchases/screens/purchase_confirmation_screen.dart';
import '../../features/qr/screens/transfer_confirmation_screen.dart';
import '../../l10n/app_localizations.dart';
import 'amount_inline.dart';
import 'quantity_circle_badge.dart';
import 'qr_generation_carnet_line.dart';
import 'transfer_line_row.dart';

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
  List<TransferConfirmationLine> lines = const [],
  String? linesTitle,
  bool showQuantity = false,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => TransferSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        recipientName: recipientName,
        lines: lines,
        linesTitle: linesTitle,
        showQuantity: showQuantity,
      ),
    ),
  );
}

Future<void> showQrGenerationSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  String? transactionReference,
  List<QrGenerationSuccessLine> lines = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => QrGenerationSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        transactionReference: transactionReference,
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
    final l10n = AppLocalizations.of(context);
    return _SuccessScaffold(
      title: l10n.purchaseSuccessTitle,
      message: l10n.purchaseSuccessMessage,
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _PurchasedLinesSection(lines: lines),
      rows: [
        _SuccessRowData(
          label: l10n.totalAmount,
          value: _totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: l10n.date,
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
    this.lines = const [],
    this.linesTitle,
    this.showQuantity = false,
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String recipientName;
  final List<TransferConfirmationLine> lines;
  final String? linesTitle;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SuccessScaffold(
      title: l10n.transferSuccessTitle,
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty
          ? null
          : _TransferredLinesSection(
              lines: lines,
              title:
                  linesTitle ??
                  (showQuantity
                      ? l10n.transferredTickets
                      : l10n.transferredCarnets),
              showQuantity: showQuantity,
            ),
      rows: [
        _SuccessRowData(
          label: l10n.beneficiary,
          value: recipientName,
          valueColor: AppColors.ink,
        ),
        _SuccessRowData(
          label: l10n.totalAmount,
          value: totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: l10n.date,
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
    this.transactionReference,
    this.lines = const [],
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String? transactionReference;
  final List<QrGenerationSuccessLine> lines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SuccessScaffold(
      title: l10n.qrGeneratedTitle,
      message: l10n.qrGeneratedMessage,
      icon: Icons.qr_code_2_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _GeneratedQrLinesSection(lines: lines),
      rows: [
        _SuccessRowData(
          label: l10n.totalAmount,
          value: totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        _SuccessRowData(
          label: l10n.date,
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
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
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
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
                  child: Text(
                    AppLocalizations.of(context).returnHome,
                    style: const TextStyle(
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
    final l10n = AppLocalizations.of(context);
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
            l10n.purchasedCarnets,
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
  const _TransferredLinesSection({
    required this.lines,
    required this.title,
    required this.showQuantity,
  });

  final List<TransferConfirmationLine> lines;
  final String title;
  final bool showQuantity;

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
            _TransferredLineRow(line: lines[i], showQuantity: showQuantity),
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
  const _TransferredLineRow({required this.line, required this.showQuantity});

  final TransferConfirmationLine line;
  final bool showQuantity;

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
    return TransferLineRow(
      title: _carnetTypeLabel(),
      quantity: line.carnetQty,
      amount: line.totalAmount,
      showQuantity: showQuantity,
    );
  }
}

class _GeneratedQrLinesSection extends StatelessWidget {
  const _GeneratedQrLinesSection({required this.lines});

  final List<QrGenerationSuccessLine> lines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            l10n.usedCarnets,
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

  String _carnetLabel(AppLocalizations l10n) {
    final raw = line.label.trim();
    if (raw.isEmpty) return l10n.carnet;
    return raw.replaceFirst(RegExp(r'^Carnet\s+', caseSensitive: false), '');
  }

  String _title(AppLocalizations l10n) {
    return l10n.ticketsFromCarnet(line.qty, _carnetLabel(l10n));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return QrGenerationCarnetLine(
      title: _title(l10n),
      amount: line.totalAmount,
      expirationDate: line.expirationDate,
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
    const rowHeight = 20.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 8,
          child: SizedBox(
            height: rowHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _carnetTypeLabel(),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: rowHeight,
            child: Center(
              child: QuantityCircleBadge(quantity: line.qty, size: rowHeight),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: rowHeight,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AmountInline(
                amount: line.totalAmount,
                textAlign: TextAlign.end,
              ),
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

  bool _isAmountRow() => RegExp(r'^\d+$').hasMatch(value.trim());

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
          child: _isAmountRow()
              ? AmountInline(amount: int.parse(value), textAlign: TextAlign.end)
              : Text(
                  value,
                  textAlign: TextAlign.end,
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
