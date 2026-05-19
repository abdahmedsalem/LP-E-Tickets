import 'package:flutter/material.dart';
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
    /// Si vrai, la flèche n’apparaît que lorsque [Navigator.canPop] (ex. racine d’onglet shell).
    this.leadingOnlyWhenNavigatorCanPop = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final bool showBack;
  final VoidCallback? onBack;
  final bool leadingOnlyWhenNavigatorCanPop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nav = Navigator.maybeOf(context);
    final canPop = nav?.canPop() ?? false;
    final effectiveShowBack =
        showBack && (!leadingOnlyWhenNavigatorCanPop || canPop);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          if (effectiveShowBack)
            _BackButton(
              onTap: onBack ?? () => nav?.maybePop(),
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          action ?? const SizedBox(width: 36),
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
      width: 36,
      height: 36,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppColors.softShadow,
            ),
            child: Icon(
              Icons.chevron_left,
              size: 20,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
