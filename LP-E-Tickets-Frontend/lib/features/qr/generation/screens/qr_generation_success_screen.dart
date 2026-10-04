import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/operation_success_scaffold.dart';
import '../../../../shared/widgets/operation_success_summary_card.dart';
import '../../../../shared/widgets/qr_generation_carnet_line.dart';

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
    return OperationSuccessScaffold(
      title: l10n.qrGeneratedTitle,
      message: l10n.qrGeneratedMessage,
      icon: Icons.qr_code_2_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _GeneratedQrLinesSection(lines: lines),
      rows: [
        OperationSuccessSummaryData(
          label: l10n.totalAmount,
          value: totalAmount.toString(),
          valueColor: const Color(0xFF2B8F3A),
        ),
        OperationSuccessSummaryData(
          label: l10n.date,
          value: Formatters.dateTimeDash(confirmedAt),
          valueColor: AppColors.ink,
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
