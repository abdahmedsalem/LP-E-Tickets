import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/amount_inline.dart';

class TransferSelectionBottomBar extends StatelessWidget {
  const TransferSelectionBottomBar({
    super.key,
    required this.totalLabel,
    required this.totalAmount,
    required this.hasSelection,
    required this.submitting,
    required this.onSubmit,
  });

  final String totalLabel;
  final int totalAmount;
  final bool hasSelection;
  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onSubmit == null || !hasSelection;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.75)),
        boxShadow: AppColors.softShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totalLabel,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AmountInline(
                    amount: totalAmount,
                    valueStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1,
                    ),
                    unitStyle: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: disabled ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43A047),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(
                  0xFF43A047,
                ).withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                elevation: 0,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).commonContinue,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
