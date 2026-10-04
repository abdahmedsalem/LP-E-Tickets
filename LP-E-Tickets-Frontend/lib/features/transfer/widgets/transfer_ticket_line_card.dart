import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/transfer_inventory.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/overview_info_card.dart';
import '../../../shared/widgets/single_line_card_title.dart';

bool _isReasonableTicketExpirationDate(DateTime date) =>
    date.year > 1971 && date.year < 2100;

String _ticketExpirationLabel(DateTime date, AppLocalizations l10n) {
  if (!_isReasonableTicketExpirationDate(date)) return l10n.expirationUnknown;
  return l10n.expiresOn(Formatters.dateTimeDash(date));
}

class TransferTicketLineCard extends StatefulWidget {
  const TransferTicketLineCard({
    super.key,
    required this.line,
    required this.carnetTypeLabel,
    required this.selected,
    required this.onChanged,
  });

  final TransferInventoryItem line;
  final String carnetTypeLabel;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<TransferTicketLineCard> createState() => _TransferTicketLineCardState();
}

class _TransferTicketLineCardState extends State<TransferTicketLineCard> {
  bool _expanded = false;

  String _ticketAvailabilityLabel(int availableQty, int carnetSize) {
    final available = Formatters.numberFr(availableQty);
    if (carnetSize > 0) {
      return '$available/${Formatters.numberFr(carnetSize)}';
    }
    return available;
  }

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
    final isSelected = widget.selected > 0;
    final availableQtyLabel = _ticketAvailabilityLabel(
      widget.line.availableQty,
      widget.line.carnetFaceCount > 0
          ? widget.line.carnetFaceCount
          : widget.line.availableQty,
    );
    final subtitleParts = <String>[
      _ticketExpirationLabel(
        widget.line.expirationDate,
        AppLocalizations.of(context),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.leaderGreen : AppColors.line,
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
              Text(
                availableQtyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDeep,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            subtitleParts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF667085),
              height: 1.08,
            ),
          ),
          const SizedBox(height: 5),
          Container(height: 1, color: const Color(0xFFEAECEF)),
          const SizedBox(height: 1),
          Row(
            children: [
              Text(
                AppLocalizations.of(context).purchaseQuantity,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              _TransferQuantityButton(
                icon: Icons.remove,
                onTap: widget.selected <= 0
                    ? null
                    : () => widget.onChanged(widget.selected - 1),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 30,
                child: Text(
                  '${widget.selected}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _TransferQuantityButton(
                icon: Icons.add,
                onTap: widget.selected >= widget.line.availableQty
                    ? null
                    : () => widget.onChanged(widget.selected + 1),
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
    );
  }
}

class _TransferQuantityButton extends StatelessWidget {
  const _TransferQuantityButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: onTap != null
            ? (icon == Icons.add
                  ? const Color(0xFF43A047)
                  : const Color(0xFFF2F4F7))
            : const Color(0xFFF3F4F6),
        foregroundColor: onTap != null
            ? (icon == Icons.add ? Colors.white : const Color(0xFF344054))
            : const Color(0xFFB8BEC7),
        disabledBackgroundColor: const Color(0xFFF3F4F6),
        disabledForegroundColor: const Color(0xFFB8BEC7),
      ),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
