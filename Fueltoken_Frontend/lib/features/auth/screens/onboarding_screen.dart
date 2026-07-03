import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/fuel_mark.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _goToRoute(BuildContext context, String route) {
    context.go(route);
  }

  Future<void> _goToLogin(BuildContext context) async {
    await AppPreferences.setHasSeenOnboarding(true);
    if (!context.mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      FuelLogo(
                        size: 34,
                        showOrgWordmark: true,
                        subtitleFuelToken: 'Tickets Carburant',
                      ),
                      Spacer(),
                    ],
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.loginHeroGradient,
                      borderRadius: BorderRadius.all(Radius.circular(28)),
                      boxShadow: AppColors.elevatedShadow,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(24, 28, 24, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.local_gas_station_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                          SizedBox(height: 22),
                          Text(
                            'Bienvenue sur Tickets Carburant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.2,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Achetez, gérez et utilisez vos carnets de tickets carburant en toute sécurité.',
                            style: TextStyle(
                              color: Color(0xFFE0F2FE),
                              fontSize: 15.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _goToRoute(context, '/register'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.leaderGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Créer mon compte',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        const Text(
                          'Vous avez déjà un compte ?',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _goToLogin(context),
                          child: const Text(
                            'Se connecter',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
