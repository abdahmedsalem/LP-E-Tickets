import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum PillTone { green, red, amber, blue, gray, yellow, dark }

/// A status pill with soft background + dark foreground.
/// Pastille de statut (fond doux + texte contrasté).
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.tone = PillTone.green,
    this.dot = false,
    this.size = AppPillSize.sm,
    this.background,
    this.foreground,
  });

  final String label;
  final PillTone tone;
  final bool dot;
  final AppPillSize size;
  final Color? background;
  final Color? foreground;

  ({Color bg, Color fg, Color dotColor}) get _palette {
    switch (tone) {
      case PillTone.green:
        return (bg: AppColors.primarySoft, fg: AppColors.primaryDark, dotColor: AppColors.primary);
      case PillTone.red:
        return (bg: AppColors.dangerSurface, fg: AppColors.danger, dotColor: AppColors.danger);
      case PillTone.amber:
        return (bg: AppColors.warningSurface, fg: const Color(0xFF92400E), dotColor: AppColors.warning);
      case PillTone.blue:
        return (bg: AppColors.infoSurface, fg: const Color(0xFF1D4ED8), dotColor: AppColors.info);
      case PillTone.gray:
        return (bg: AppColors.lineSoft, fg: AppColors.body, dotColor: AppColors.muted);
      case PillTone.yellow:
        return (bg: AppColors.brandYellowSoft, fg: const Color(0xFF92580E), dotColor: AppColors.brandYellow);
      case PillTone.dark:
        return (bg: AppColors.ink, fg: Colors.white, dotColor: AppColors.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final bg = background ?? p.bg;
    final fg = foreground ?? p.fg;
    final isLg = size == AppPillSize.lg;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLg ? 10 : 8, vertical: isLg ? 5 : 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: p.dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: isLg ? 12 : 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

enum AppPillSize { sm, lg }
