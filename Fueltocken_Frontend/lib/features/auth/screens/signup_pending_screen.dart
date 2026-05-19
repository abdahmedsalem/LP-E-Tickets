import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_role.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../bloc/auth_bloc.dart';

/// Extra for [GoRouter] route `/signup/pending`.
class SignupPendingRouteArgs {
  const SignupPendingRouteArgs({
    required this.identifier,
    required this.password,
  });

  final String identifier;
  final String password;
}

/// Après inscription ACPEC : attente validation admin, puis connexion automatique par tentative répétée.
class SignupPendingScreen extends StatefulWidget {
  const SignupPendingScreen({super.key, required this.args});

  final SignupPendingRouteArgs args;

  @override
  State<SignupPendingScreen> createState() => _SignupPendingScreenState();
}

class _SignupPendingScreenState extends State<SignupPendingScreen> {
  Timer? _timer;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _pollLogin());
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollLogin());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _messageLooksRejected(String raw) {
    final m = raw.toLowerCase();
    const markers = [
      'reject',
      'rejet',
      'refus',
      'refused',
      'denied',
      'declined',
      'réfus',
    ];
    return markers.any((k) => m.contains(k));
  }

  Future<void> _pollLogin() async {
    if (_inFlight || !mounted) return;
    _inFlight = true;
    try {
      final user = await AuthRepository.instance.login(
        widget.args.identifier.trim(),
        widget.args.password,
      );
      if (!mounted) return;
      await LoginSessionCache.saveLastLogin(
        identifier: widget.args.identifier.trim(),
        password: widget.args.password,
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthSessionEstablished(user));
      _timer?.cancel();
      final path = switch (user.role) {
        UserRole.admin => '/admin',
        UserRole.station => '/station',
        UserRole.user => '/home',
      };
      if (!mounted) return;
      context.go(path);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (_messageLooksRejected(msg) && mounted) {
        _timer?.cancel();
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Demande refusée'),
            content: Text(
              msg.trim().isEmpty
                  ? 'Votre demande de compte a été refusée. Contactez le support si besoin.'
                  : msg,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/login');
      }
    } finally {
      _inFlight = false;
    }
  }

  void _goLogin() {
    _timer?.cancel();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: 'Validation',
              subtitle: 'En attente',
              onBack: _goLogin,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const AppLoadingLottie(size: 56),
                        const SizedBox(height: 28),
                        const Text(
                          'Demande envoyée',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Un administrateur doit approuver votre compte. '
                          'Connexion automatique dès validation…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: AppColors.muted.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextButton(
                          onPressed: _goLogin,
                          child: const Text('Retour à la connexion'),
                        ),
                      ],
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
