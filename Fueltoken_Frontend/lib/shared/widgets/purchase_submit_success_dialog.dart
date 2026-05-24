import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/acpec_purchase_create_result.dart';

/// Dialogue après création réussie d’une commande de carnets (Odoo ACPEC).
Future<void> showPurchaseSubmitSuccessDialog(
  BuildContext context, {
  required AcpecPurchaseCreateResult result,
  String? clientPaymentReference,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PurchaseSuccessDialog(
      result: result,
      clientPaymentReference: clientPaymentReference,
    ),
  );
}

class _PurchaseSuccessDialog extends StatelessWidget {
  const _PurchaseSuccessDialog({
    required this.result,
    this.clientPaymentReference,
  });

  final AcpecPurchaseCreateResult result;
  final String? clientPaymentReference;

  static String _stateLabelFr(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'submitted':
      case 'sent':
      case 'pending':
      case 'waiting':
        return 'En attente';
      case 'draft':
        return 'Brouillon';
      case 'approved':
      case 'done':
      case 'sale':
        return 'Validé';
      case 'rejected':
      case 'cancel':
      case 'cancelled':
        return 'Rejeté';
      default:
        return raw.isEmpty ? '—' : raw;
    }
  }

  static Color _stateColor(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'submitted':
      case 'sent':
      case 'pending':
      case 'waiting':
        return const Color(0xFF0E7C66);
      case 'draft':
        return AppColors.muted;
      case 'approved':
      case 'done':
      case 'sale':
        return AppColors.leaderGreenDark;
      case 'rejected':
      case 'cancel':
      case 'cancelled':
        return AppColors.brandRed;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0E7C66),
                    Color(0xFF0D6FCB),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Commande enregistrée',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Votre demande a été transmise au serveur ACPEC.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailCard(
                    scheme: scheme,
                    label: 'État',
                    value: '',
                    chip: _StateChip(
                      displayLabel: _stateLabelFr(result.state),
                      color: _stateColor(result.state),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Text(
                'Votre demande sera traitée après validation.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outline.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Terminer',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.displayLabel,
    required this.color,
  });

  final String displayLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            displayLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.scheme,
    required this.label,
    required this.value,
    this.chip,
  });

  final ColorScheme scheme;
  final String label;
  final String value;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.85,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                if (chip != null)
                  chip!
                else
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


