import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/pending_signup_store.dart';
import '../../../core/config/app_brand_config.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_role.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/fuel_mark.dart';
import '../bloc/auth_bloc.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    _completeSplash();
  }

  Future<void> _completeSplash() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final s = context.read<AuthBloc>().state;
      if (s.status == AuthStatus.authenticated && s.user != null) {
        if (!mounted) return;
        switch (s.user!.role) {
          case UserRole.user:
            context.go('/home');
            break;
          case UserRole.admin:
            context.go('/admin');
            break;
          case UserRole.station:
            context.go('/station');
            break;
        }
        return;
      }
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
    if (!mounted) return;
    final s = context.read<AuthBloc>().state;
    if (s.status == AuthStatus.authenticated && s.user != null) {
      if (!mounted) return;
      switch (s.user!.role) {
        case UserRole.user:
          context.go('/home');
          break;
        case UserRole.admin:
          context.go('/admin');
          break;
        case UserRole.station:
          context.go('/station');
          break;
      }
    } else {
      if (!mounted) return;
      final hasSelectedLanguage = await AppPreferences.hasSelectedLanguage();
      if (!mounted) return;
      if (!hasSelectedLanguage) {
        context.go('/language-selection');
        return;
      }
      final pendingSignup = await PendingSignupStore.loadUsable();
      if (!mounted) return;
      if (pendingSignup != null) {
        context.go('/register/verify-otp');
        return;
      }
      final seenOnboarding = await AppPreferences.hasSeenOnboarding();
      if (!mounted) return;
      context.go(seenOnboarding ? '/login' : '/onboarding');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            PositionedDirectional(
              top: -110,
              end: -90,
              child: _GlowBlob(
                size: 280,
                color: AppColors.successSurface.withValues(alpha: 0.78),
              ),
            ),
            PositionedDirectional(
              bottom: -120,
              start: -80,
              child: _GlowBlob(
                size: 250,
                color: AppColors.brandBlueSoft.withValues(alpha: 0.72),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: FadeTransition(
                      opacity: _fade,
                      child: ScaleTransition(
                        scale: _scale,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.loginHeroGradient,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(30),
                            ),
                            boxShadow: AppColors.elevatedShadow,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.16,
                                        ),
                                        blurRadius: 30,
                                        offset: const Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: FuelMark(size: 62),
                                  ),
                                ),
                                const SizedBox(height: 26),
                                Text(
                                  AppLocalizations.of(context).authBrandName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.8,
                                    height: 1.08,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).authSplashTagline,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFE0F2FE),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                                if (AppBrandConfig
                                    .operatorTagline
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      AppBrandConfig.operatorTagline,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 30),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: SizedBox(
                                    width: 54,
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
