import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/operation_success_scaffold.dart';
import '../../../shared/widgets/operation_success_summary_card.dart';
import '../models/transfer_confirmation.dart';
import '../widgets/transfer_success_details.dart';

Future<void> showTransferTicketsSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  required String recipientName,
  List<TransferConfirmationLine> lines = const [],
  String? linesTitle,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => TransferTicketsSuccessScreen(
        totalAmount: totalAmount,
        confirmedAt: confirmedAt,
        recipientName: recipientName,
        lines: lines,
        linesTitle: linesTitle,
      ),
    ),
  );
}

class TransferTicketsSuccessScreen extends StatelessWidget {
  const TransferTicketsSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.confirmedAt,
    required this.recipientName,
    this.lines = const [],
    this.linesTitle,
  });

  final int totalAmount;
  final DateTime confirmedAt;
  final String recipientName;
  final List<TransferConfirmationLine> lines;
  final String? linesTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OperationSuccessScaffold(
      title: l10n.transferSuccessTitle,
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty
          ? null
          : TransferredLinesSection(
              lines: lines,
              title: linesTitle ?? l10n.transferredTickets,
              showQuantity: true,
            ),
      rows: [
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
