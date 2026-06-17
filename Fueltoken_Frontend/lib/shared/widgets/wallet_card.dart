import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import 'mini_stat.dart';

/// Premium wallet hero — bank-style frame, depth, frosted breakdown.
class WalletGradientCard extends StatelessWidget {
  const WalletGradientCard({
    super.key,
    required this.amount,
    this.miniStats = const [],
    this.eyebrow,
    this.subtitle,
    this.currency = Formatters.fallbackCurrency,
    this.onTap,
    this.onEyeTap,
  });

  final num amount;
  final List<MiniStat> miniStats;
  final String? eyebrow;
  final String? subtitle;
  final String currency;
  final VoidCallback? onTap;
  final VoidCallback? onEyeTap;

  static const _r = 28.0;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_r),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_r + 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B1220).withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 16),
              spreadRadius: -10,
            ),
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.28),
              blurRadius: 40,
              offset: const Offset(0, 20),
              spreadRadius: -14,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_r),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.45),
                        Colors.white.withValues(alpha: 0.08),
                        AppColors.brandBlueDeep.withValues(alpha: 0.4),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(1.5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_r - 1),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.walletGradient,
                        ),
                      ),
                      // Top studio sheen
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 120,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -60,
                        right: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentViolet.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -70,
                        left: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentTeal.withValues(alpha: 0.16),
                          ),
                        ),
                      ),
                      // Subtle noise / depth vignette
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.15, -0.35),
                              radius: 1.15,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.12),
                              ],
                              stops: const [0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (eyebrow != null && eyebrow!.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      eyebrow!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  )
                                else
                                  const Spacer(),
                                if (onEyeTap != null)
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: onEyeTap,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.visibility_outlined,
                                          size: 19,
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      Formatters.numberFr(amount),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 39,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.3,
                                        height: 1,
                                        shadows: [
                                          Shadow(
                                            color: Color(0x33000000),
                                            blurRadius: 12,
                                            offset: Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  currency,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.68),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (miniStats.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < miniStats.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(width: 8),
                                      miniStats[i],
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
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
