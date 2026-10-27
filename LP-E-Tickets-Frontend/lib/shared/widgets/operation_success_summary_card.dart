import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'amount_inline.dart';

class OperationSuccessSummaryData {
  const OperationSuccessSummaryData({
    required this.label,
    required this.value,
    required this.valueColor,
    this.displayAsAmount = true,
    this.labelFlex = 3,
    this.valueFlex = 2,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool displayAsAmount;
  final int labelFlex;
  final int valueFlex;
}

class OperationSuccessSummaryCard extends StatelessWidget {
  const OperationSuccessSummaryCard({
    super.key,
    required this.rows,
    this.showDividers = false,
  });

  final List<OperationSuccessSummaryData> rows;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            _OperationSuccessSummaryRow(data: rows[i]),
            if (i < rows.length - 1 && showDividers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE5E7EB),
                ),
              )
            else if (i < rows.length - 1)
              const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _OperationSuccessSummaryRow extends StatelessWidget {
  const _OperationSuccessSummaryRow({required this.data});

  final OperationSuccessSummaryData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: data.labelFlex,
          child: Text(
            data.label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: data.valueFlex,
          child:
              data.displayAsAmount &&
                  RegExp(r'^\d+$').hasMatch(data.value.trim())
              ? AmountInline(
                  amount: int.parse(data.value),
                  textAlign: TextAlign.end,
                )
              : Text(
                  data.value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: data.valueColor,
                  ),
                ),
        ),
      ],
    );
  }
}
