import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'operation_success_summary_card.dart';

class OperationSuccessScaffold extends StatelessWidget {
  const OperationSuccessScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.rows,
    this.details,
    this.message,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Color accentColor;
  final List<OperationSuccessSummaryData> rows;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAF8EC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: accentColor, size: 40),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (details != null) ...[
                      details!,
                      const SizedBox(height: 18),
                    ],
                    OperationSuccessSummaryCard(rows: rows),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).returnHome,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
