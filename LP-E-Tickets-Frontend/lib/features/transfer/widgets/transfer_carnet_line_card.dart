import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/transfer_inventory.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/overview_info_card.dart';
import '../../../shared/widgets/single_line_card_title.dart';

bool _isReasonableExpirationDate(DateTime date) =>
    date.year > 1971 && date.year < 2100;

String _expirationLabel(DateTime date, AppLocalizations l10n) {
  if (!_isReasonableExpirationDate(date)) return l10n.expirationUnknown;
  return l10n.expiresOn(Formatters.dateTimeDash(date));
}

class TransferCarnetLineCard extends StatefulWidget {
  const TransferCarnetLineCard({
    super.key,
    required this.line,
    required this.carnetTypeLabel,
    required this.carnetSize,
    required this.selected,
    required this.onTap,
  });

  final TransferInventoryItem line;
  final String carnetTypeLabel;
  final int carnetSize;
  final int selected;
  final VoidCallback onTap;

  @override
  State<TransferCarnetLineCard> createState() => _TransferCarnetLineCardState();
}

class _TransferCarnetLineCardState extends State<TransferCarnetLineCard> {
  bool _expanded = false;

  String _referenceCode() {
    final shortCode = widget.line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) return shortCode;
    final typeCode = widget.line.carnetTypeCode.trim();
    if (typeCode.isNotEmpty) return typeCode;
    final carnetNo = widget.line.carnetNo.trim();
    if (carnetNo.isNotEmpty) return carnetNo;
    return AppLocalizations.of(context).carnetCodeUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final transferableValue =
        (line.availableQty ~/ widget.carnetSize) *
        widget.carnetSize *
        line.faceValue;
    final isSelected = widget.selected > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.leaderGreen
                  : const Color(0xFFEAECEF),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleLineCardTitle(
                      text: widget.carnetTypeLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AmountInline(amount: transferableValue),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: _expirationLabel(
                          line.expirationDate,
                          AppLocalizations.of(context),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: AppColors.muted,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: OverviewInfoCard(
                          items: [
                            OverviewInfoItem(
                              label: AppLocalizations.of(
                                context,
                              ).referenceIdentifier,
                              value: _referenceCode(),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
