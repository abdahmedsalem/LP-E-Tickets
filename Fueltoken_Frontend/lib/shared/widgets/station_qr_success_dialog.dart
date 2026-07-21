import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'operation_success_summary_card.dart';
import 'station_popup_frame.dart';

class StationQrSuccessDialog extends StatelessWidget {
  const StationQrSuccessDialog({
    super.key,
    required this.amount,
    required this.consumedAt,
    required this.transactionName,
    required this.onClose,
  });

  final String amount;
  final String consumedAt;
  final String transactionName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StationPopupFrame(
      title: l10n.stationQrConsumedSuccess,
      message: l10n.stationConsumptionRecorded,
      icon: Icons.check_rounded,
      accentColor: AppColors.leaderGreen,
      iconBackgroundColor: AppColors.successSurface,
      accentGradient: AppColors.validGradient,
      actionLabel: l10n.stationFinish,
      onAction: onClose,
      maxHeightFactor: 0.86,
      content: OperationSuccessSummaryCard(
        rows: [
          OperationSuccessSummaryData(
            label: l10n.amount,
            value: amount,
            valueColor: AppColors.success,
          ),
          OperationSuccessSummaryData(
            label: l10n.stationDateTime,
            value: consumedAt,
            valueColor: AppColors.ink,
          ),
          OperationSuccessSummaryData(
            label: l10n.stationTransactionNumber,
            value: transactionName,
            valueColor: AppColors.ink,
          ),
        ],
      ),
    );
  }
}
