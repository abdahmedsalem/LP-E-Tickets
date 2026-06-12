import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Custom in-screen app bar header — small back chevron, title + optional
/// subtitle, optional trailing action.
class AppBarHeader extends StatelessWidget {
  const AppBarHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.showBack = true,
    this.onBack,
    this.largeTitle = false,
    this.largeTitlePadding,
    this.largeTitleGap,
    this.largeTitleFontSize,
    this.plainBackButton = false,

    /// Si vrai, la flèche n’apparaît que lorsque [Navigator.canPop] (ex. racine d’onglet shell).
    this.leadingOnlyWhenNavigatorCanPop = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final bool showBack;
  final VoidCallback? onBack;
  final bool largeTitle;
  final EdgeInsetsGeometry? largeTitlePadding;
  final double? largeTitleGap;
  final double? largeTitleFontSize;
  final bool plainBackButton;
  final bool leadingOnlyWhenNavigatorCanPop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nav = Navigator.maybeOf(context);
    final canPop = nav?.canPop() ?? false;
    final effectiveShowBack =
        showBack && (!leadingOnlyWhenNavigatorCanPop || canPop);

    if (largeTitle) {
      return Padding(
        padding: largeTitlePadding ?? const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (effectiveShowBack)
                  _HeroBackButton(onTap: onBack ?? () => nav?.maybePop())
                else
                  const SizedBox(width: 32, height: 32),
                const Spacer(),
                if (action != null) ...[action!],
              ],
            ),
            SizedBox(height: largeTitleGap ?? 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: largeTitleFontSize ?? 26,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                letterSpacing: -0.6,
                height: 1.08,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Row(
        children: [
          if (effectiveShowBack)
            plainBackButton
                ? _HeroBackButton(onTap: onBack ?? () => nav?.maybePop())
                : _BackButton(onTap: onBack ?? () => nav?.maybePop())
          else
            const SizedBox(width: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action ?? const SizedBox(width: 40, height: 40),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(14),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppColors.softShadow,
            ),
            child: Icon(Icons.chevron_left, size: 22, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _HeroBackButton extends StatelessWidget {
  const _HeroBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: const Center(
            child: Icon(
              Icons.arrow_back_rounded,
              size: 22,
              color: Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
