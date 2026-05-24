import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_brand_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_role.dart';
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
    _scale = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
      context.go('/login');
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
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.splashGradient),
          child: Stack(
            children: [
              // Top-right green glow
              Positioned(
                top: -80,
                right: -80,
                child: _GlowBlob(
                  size: 280,
                  color: AppColors.leaderGreen.withValues(alpha: 0.22),
                ),
              ),
              // Bas-droite — teal léger
              Positioned(
                bottom: -100,
                right: -60,
                child: _GlowBlob(
                  size: 240,
                  color: AppColors.accentTeal.withValues(alpha: 0.18),
                ),
              ),
              SafeArea(
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // White rounded square holding the brand mark.
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.20),
                                    blurRadius: 40,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: const Center(child: FuelMark(size: 52)),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'FuelToken',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1,
                              ),
                            ),
                            if (AppBrandConfig.operatorTagline.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppBrandConfig.operatorTagline,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 60),
                            Text(
                              'Bons carburant traçables',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
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
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
