import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Logo marque PNG fond transparent — carte solde accueil.
class _ClientWalletBrandLogo extends StatelessWidget {
  const _ClientWalletBrandLogo({required this.size});

  final double size;

  static const _asset = 'assets/images/logo_fueltoken.png';

  /// Fichier PNG large : la flamme est à gauche du canvas — on croppe à gauche.
  static const _assetWidthFactor = 3.8;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: size * _assetWidthFactor,
          maxHeight: size,
          alignment: Alignment.centerLeft,
          child: Image.asset(
            _asset,
            height: size,
            fit: BoxFit.fitHeight,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => Icon(
              Icons.local_gas_station_rounded,
              size: size * 0.45,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

/// Illustration Lottie (station / marque) — `assets/lottie/gas_station.json`.
class FuelBrandLottie extends StatelessWidget {
  const FuelBrandLottie({
    super.key,
    required this.size,
    this.fit = BoxFit.contain,
  });

  final double size;
  final BoxFit fit;

  static const _asset = 'assets/lottie/gas_station.json';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        _asset,
        fit: fit,
        repeat: true,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.local_gas_station_rounded,
          size: size * 0.45,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

/// Carte solde accueil client (vert + logo à droite).
class ClientHomeWalletCard extends StatelessWidget {
  const ClientHomeWalletCard({
    super.key,
    required this.amount,
    required this.totalTickets,
  });

  final int amount;
  final int totalTickets;

  static const _r = 26.0;
  /// Logo lanceur (~46 px visuel) ×3, superposé à droite sans agrandir la carte.
  static const _logoSide = 138.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_r + 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF064E3B).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_r),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: AppColors.clientHomeWalletGradient,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 98, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SOLDE PORTEFEUILLE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          Formatters.numberFr(amount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                            height: 1,
                            shadows: [
                              Shadow(
                                color: Color(0x33000000),
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'MRU',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wallet_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${Formatters.numberFr(totalTickets)} tickets disponibles',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Votre solde est à jour',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: 0.95,
                  child: _ClientWalletBrandLogo(size: _logoSide),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
