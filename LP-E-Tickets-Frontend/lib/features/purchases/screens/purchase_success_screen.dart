import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/purchase/purchase_receipt.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/operation_success_scaffold.dart';
import '../../../shared/widgets/operation_success_summary_card.dart';
import '../../../shared/widgets/quantity_circle_badge.dart';
import 'purchase_confirmation_screen.dart';

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
    return OperationSuccessScaffold(
      title: l10n.purchaseSuccessTitle,
      message: l10n.purchaseSuccessMessage,
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF2B8F3A),
      details: lines.isEmpty ? null : _PurchasedLinesSection(lines: lines),
      rows: [
        OperationSuccessSummaryData(
          label: l10n.totalAmount,
          value: _totalAmount.toString(),
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

class _PurchasedLineRow extends StatelessWidget {
  const _PurchasedLineRow({required this.line});

  final PurchaseConfirmationLine line;

  String _carnetTypeLabel(AppLocalizations l10n) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetType.name,
      fallbackCode: line.carnetType.code,
    );
    return label.isNotEmpty ? label : l10n.carnet;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  _carnetTypeLabel(l10n),
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
