import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_bar_header.dart';

const _confirmationHeaderPadding = EdgeInsets.fromLTRB(12, 8, 12, 0);
const _confirmationHeaderGap = 10.0;
const _confirmationHeaderTitleSize = 26.0;

class QrActionConfirmationArgs {
  const QrActionConfirmationArgs({
    required this.title,
    required this.confirmLabel,
    required this.hero,
    required this.summaryRows,
    this.subtitle,
    this.details,
    this.disclaimer,
    this.showHero = true,
  });

  final String title;
  final String confirmLabel;
  final String? subtitle;
  final Widget hero;
  final Widget? details;
  final List<QrActionSummaryRow> summaryRows;
  final String? disclaimer;
  final bool showHero;
}

class QrActionSummaryRow {
  const QrActionSummaryRow({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;
}

class QrActionConfirmationScreen extends StatelessWidget {
  const QrActionConfirmationScreen({super.key, required this.args});

  final QrActionConfirmationArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    args.confirmLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: args.title,
              onBack: () => Navigator.of(context).pop(false),
              largeTitle: true,
              largeTitlePadding: _confirmationHeaderPadding,
              largeTitleGap: _confirmationHeaderGap,
              largeTitleFontSize: _confirmationHeaderTitleSize,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (args.showHero) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2FBF3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFCFE8D1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (args.subtitle != null) ...[
                            Text(
                              args.subtitle!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          args.hero,
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (args.details != null) ...[
                    args.details!,
                    const SizedBox(height: 20),
                  ],
                  if (args.summaryRows.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < args.summaryRows.length; i++) ...[
                            _SummaryRow(
                              label: args.summaryRows[i].label,
                              value: args.summaryRows[i].value,
                              valueColor: args.summaryRows[i].valueColor,
                            ),
                            if (i < args.summaryRows.length - 1)
                              const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (args.disclaimer != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      args.disclaimer!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  bool _looksLikeAmount(String text) =>
      RegExp(r'^\s*[\d\s.,]+\s*MRU\s*$').hasMatch(text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.body,
            ),
          ),
        ),
        if (_looksLikeAmount(value))
          _AmountInline(
            amount: int.parse(value.replaceAll(RegExp(r'[^0-9]'), '').trim()),
            textAlign: TextAlign.right,
            valueStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
            unitStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: valueColor.withValues(alpha: 0.82),
            ),
          )
        else
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
      ],
    );
  }
}

class _AmountInline extends StatelessWidget {
  const _AmountInline({
    required this.amount,
    required this.valueStyle,
    required this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
          TextSpan(text: ' MRU', style: unitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
