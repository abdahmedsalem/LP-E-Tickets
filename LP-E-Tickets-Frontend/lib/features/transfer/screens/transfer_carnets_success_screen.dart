import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/operation_success_scaffold.dart';
import '../../../shared/widgets/operation_success_summary_card.dart';
import '../models/transfer_confirmation.dart';
import '../widgets/transfer_success_details.dart';

Future<void> showTransferCarnetsSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  required String recipientName,
  String? operationReference,
  List<TransferConfirmationLine> lines = const [],
  String? linesTitle,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => TransferCarnetsSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        recipientName: recipientName,
        operationReference: operationReference,
        lines: lines,
        linesTitle: linesTitle,
      ),
    ),
  );
}

class TransferCarnetsSuccessScreen extends StatelessWidget {
  const TransferCarnetsSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.confirmedAt,
    required this.recipientName,
    this.operationReference,
    this.lines = const [],
    this.linesTitle,
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String recipientName;
  final String? operationReference;
  final List<TransferConfirmationLine> lines;
  final String? linesTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OperationSuccessScaffold(
      title: l10n.transferSuccessTitle,
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      showSummaryDividers: true,
      details: lines.isEmpty
          ? null
          : TransferredLinesSection(
              lines: lines,
              title: linesTitle ?? l10n.transferredCarnets,
              showQuantity: false,
            ),
      rows: [
        if (operationReference != null && operationReference!.isNotEmpty)
          OperationSuccessSummaryData(
            label: l10n.operationReference,
            value: operationReference!,
            valueColor: AppColors.ink,
            displayAsAmount: false,
          ),
        OperationSuccessSummaryData(
          label: l10n.beneficiary,
          value: recipientName,
          valueColor: AppColors.ink,
        ),
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
