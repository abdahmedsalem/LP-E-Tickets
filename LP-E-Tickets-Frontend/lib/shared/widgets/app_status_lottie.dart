import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_colors.dart';

/// Lottie « chargement » plein écran / zone large (`loading_indicator.json`).
class AppLoadingLottie extends StatelessWidget {
  const AppLoadingLottie({
    super.key,
    this.size = 120,
    this.fit = BoxFit.contain,
  });

  final double size;
  final BoxFit fit;

  static const asset = 'assets/lottie/loading_indicator.json';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        fit: fit,
        repeat: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Lottie « erreur / échec ».
class AppErrorLottie extends StatelessWidget {
  const AppErrorLottie({super.key, this.size = 140, this.fit = BoxFit.contain});

  final double size;
  final BoxFit fit;

  static const asset = 'assets/lottie/error_feedback.json';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        fit: fit,
        repeat: false,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Icon(
          Icons.error_outline_rounded,
          size: size * 0.45,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

/// Placeholder de page : animation centrée sur fond écran (pas de carré blanc).
class AppPageLoading extends StatelessWidget {
  const AppPageLoading({super.key, this.size = 132});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(child: AppLoadingLottie(size: size)),
    );
  }
}

/// Lottie « succès » (consommation validée, etc.) — une lecture.
class AppSuccessLottie extends StatelessWidget {
  const AppSuccessLottie({
    super.key,
    this.size = 120,
    this.fit = BoxFit.contain,
  });

  final double size;
  final BoxFit fit;

  static const asset = 'assets/lottie/gas_station.json';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        fit: fit,
        repeat: false,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Icon(
          Icons.check_circle_rounded,
          size: size * 0.5,
          color: AppColors.success,
        ),
      ),
    );
  }
}

/// Indicateur compact pour boutons et icônes (pas de Lottie).
class AppInlineLoading extends StatelessWidget {
  const AppInlineLoading({
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 2.4,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
