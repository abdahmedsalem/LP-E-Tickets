import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';

class DateRangeFilterBar extends StatefulWidget {
  const DateRangeFilterBar({
    super.key,
    required this.initialFrom,
    required this.initialTo,
    required this.onApply,
    this.firstDate,
    this.lastDate,
  });

  final DateTime initialFrom;
  final DateTime initialTo;
  final ValueChanged<DateTimeRange> onApply;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<DateRangeFilterBar> createState() => _DateRangeFilterBarState();
}

class _DateRangeFilterBarState extends State<DateRangeFilterBar> {
  static const double _controlHeight = 38;

  late DateTime _draftFrom;
  late DateTime _draftTo;

  @override
  void initState() {
    super.initState();
    _syncDraftDates();
  }

  @override
  void didUpdateWidget(covariant DateRangeFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(widget.initialFrom, oldWidget.initialFrom) ||
        !_sameDay(widget.initialTo, oldWidget.initialTo)) {
      _syncDraftDates();
    }
  }

  void _syncDraftDates() {
    _draftFrom = _startOfDay(widget.initialFrom);
    _draftTo = _startOfDay(widget.initialTo);
  }

  DateTime get _firstDate => widget.firstDate ?? DateTime(2020);

  DateTime get _lastDate =>
      widget.lastDate ?? DateTime.now().add(const Duration(days: 365));

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draftFrom,
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draftFrom = _startOfDay(picked);
      if (_draftFrom.isAfter(_draftTo)) _draftTo = _draftFrom;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draftTo,
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draftTo = _startOfDay(picked);
      if (_draftTo.isBefore(_draftFrom)) _draftFrom = _draftTo;
    });
  }

  void _apply() {
    widget.onApply(
      DateTimeRange(start: _startOfDay(_draftFrom), end: _endOfDay(_draftTo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Flexible(
          flex: 43,
          child: _DateRangeChip(
            label: l10n.dateFrom,
            value: Formatters.date(_draftFrom),
            onTap: _pickFrom,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          flex: 43,
          child: _DateRangeChip(
            label: l10n.dateTo,
            value: Formatters.date(_draftTo),
            onTap: _pickTo,
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: const Color(0xFF1B8F3A),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _apply,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 42,
              height: _controlHeight,
              child: Semantics(
                label: l10n.dateApply,
                button: true,
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: _DateRangeFilterBarState._controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF374151), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Color(0xFF374151),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
