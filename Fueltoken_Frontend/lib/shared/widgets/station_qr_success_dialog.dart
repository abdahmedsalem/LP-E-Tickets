import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 390, maxHeight: maxHeight),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 7,
                  decoration: const BoxDecoration(
                    gradient: AppColors.validGradient,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: AppColors.successSurface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.18),
                            width: 5,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 42,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'QR consommé avec succès',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.35,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'La consommation a bien été enregistrée.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          children: [
                            _SuccessInfoLine(
                              label: 'Montant',
                              value: amount,
                              valueColor: AppColors.success,
                              emphasized: true,
                            ),
                            const SizedBox(height: 16),
                            _SuccessInfoLine(
                              label: 'Date/heure',
                              value: consumedAt,
                            ),
                            const SizedBox(height: 16),
                            _SuccessInfoLine(
                              label: 'N° transaction',
                              value: transactionName,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: onClose,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.leaderGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Terminer',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessInfoLine extends StatelessWidget {
  const _SuccessInfoLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: emphasized ? 17 : 13.5,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
