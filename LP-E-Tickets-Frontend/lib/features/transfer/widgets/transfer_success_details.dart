import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../models/transfer_confirmation.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/transfer_line_row.dart';

class TransferredLinesSection extends StatelessWidget {
  const TransferredLinesSection({
    super.key,
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

  String _carnetTypeLabel(AppLocalizations l10n) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.item.carnetTypeName,
      fallbackCode: line.item.carnetTypeCode,
    );
    return label.isNotEmpty ? label : l10n.carnet;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TransferLineRow(
      title: _carnetTypeLabel(l10n),
      quantity: line.quantity,
      amount: line.totalAmount,
      showQuantity: showQuantity,
    );
  }
}
