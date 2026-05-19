import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/config/app_brand_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../shared/widgets/app_alert_dialog.dart';
import '../bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _handlingAuthMessage = false;
  bool _biometricUnlockStarted = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _hydrateIdentifier();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _tryUnlockWithBiometrics());
  }

  Future<void> _hydrateIdentifier() async {
    final id = await LoginSessionCache.lastIdentifier();
    if (!mounted) return;
    if (id != null && id.isNotEmpty) {
      _identifier.text = id;
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  String _presentLoginFailure(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return 'Identifiants ou mot de passe incorrects.';
    }
    // Erreurs JSON-RPC / réseau (souvent > 160 car.) : les afficher pour diagnostic
    // (ex. mauvaise ODOO_JSONRPC_BASE_URL depuis un téléphone).
    if (t.length > 900) {
      return '${t.substring(0, 900)}…';
    }
    return t;
  }

  Future<void> _tryUnlockWithBiometrics() async {
    if (_biometricUnlockStarted) return;
    final enabled = await LoginSessionCache.biometricPreferred();
    if (!enabled || !mounted) return;
    final id = await LoginSessionCache.lastIdentifier();
    final pw = await LoginSessionCache.lastPassword();
    if (id == null || pw == null || id.isEmpty || pw.isEmpty) return;
    if (!mounted) return;
    final authBloc = context.read<AuthBloc>();
    final s = authBloc.state;
    if (s.status == AuthStatus.authenticated ||
        s.status == AuthStatus.authenticating) {
      return;
    }

    _biometricUnlockStarted = true;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Accédez à votre espace FuelToken.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok || !mounted) {
        _biometricUnlockStarted = false;
        return;
      }
      authBloc.add(AuthLoginRequested(identifier: id, password: pw));
    } on PlatformException {
      if (mounted) _biometricUnlockStarted = false;
    }
  }

  static String? _validateIdentifier(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Saisissez votre email ou téléphone';
    }
    final t = v.trim();
    if (t.contains('@')) {
      return validateAppEmail(t);
    }
    var digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('222')) {
      digits = digits.substring(3);
    }
    return validateMrLocalPhone(digits);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) =>
              a.status != b.status ||
              a.errorMessage != b.errorMessage ||
              a.loginInfoMessage != b.loginInfoMessage,
          listener: (ctx, state) async {
            if (state.status == AuthStatus.unauthenticated &&
                state.loginInfoMessage != null) {
              _biometricUnlockStarted = false;
            }
            if (state.status == AuthStatus.authenticated) {
              final id = _identifier.text.trim();
              var pw = _password.text;
              if (pw.isEmpty) {
                pw = await LoginSessionCache.lastPassword() ?? '';
              }
              if (id.isNotEmpty && pw.isNotEmpty) {
                await LoginSessionCache.saveLastLogin(
                  identifier: id,
                  password: pw,
                );
              }
              // La navigation après connexion est gérée par [AppRouter] via
              // `redirect` (`loggedIn && atAuthRoute` → `/home` | `/admin` | `/station`).
              // Ne pas utiliser GoRouterState.of / ctx.go ici : après un await, le
              // contexte du listener peut ne plus être sous le RouteMatch (GoError).
            }
            if (state.status == AuthStatus.failure) {
              _biometricUnlockStarted = false;
            }
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null &&
                !_handlingAuthMessage) {
              _handlingAuthMessage = true;
              final msg = _presentLoginFailure(state.errorMessage!);
              if (ctx.mounted) {
                await showAppAlertDialog(
                  ctx,
                  title: 'Connexion',
                  message: msg,
                  confirmLabel: 'Fermer',
                  isError: true,
                  icon: Icons.gpp_maybe_outlined,
                );
              }
              _handlingAuthMessage = false;
            }
          },
          builder: (ctx, state) {
            final loading = state.status == AuthStatus.authenticating;
            return LayoutBuilder(
              builder: (context, constraints) {
                final heroH = (constraints.maxHeight * 0.32)
                    .clamp(198.0, 268.0)
                    .toDouble();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: heroH,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: AppColors.loginHeroGradient,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(36),
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              top: -40,
                              right: -24,
                              child: ExcludeSemantics(
                                child: Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -36,
                              left: -28,
                              child: ExcludeSemantics(
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.leaderGreen.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SafeArea(
                              bottom: false,
                              child: LayoutBuilder(
                                builder: (context, inner) {
                                  const padV = 8.0;
                                  const padBottom = 20.0;
                                  const gap = 16.0;
                                  const textReserve = 60.0;
                                  final avail =
                                      inner.maxHeight - padV - padBottom;
                                  final raw = avail - gap - textReserve;
                                  final logoH = raw.clamp(0.0, 132.0);
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      padV,
                                      24,
                                      padBottom,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (logoH >= 36)
                                          Image.asset(
                                            'assets/images/logo_fueltoken.png',
                                            height: logoH,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.centerLeft,
                                            filterQuality:
                                                FilterQuality.medium,
                                          ),
                                        if (logoH >= 36) SizedBox(height: gap),
                                        Text(
                                          'Espace carburant',
                                          style: TextStyle(
                                            fontSize: 20,
                                            height: 1.2,
                                            letterSpacing: -0.5,
                                            color: Colors.white.withValues(
                                              alpha: 0.98,
                                            ),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Accès sécurisé à votre '
                                          'espace carburant',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.35,
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: _PremiumLoginPanel(
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const _CardHeader(),
                                    if (state.loginInfoMessage != null) ...[
                                      const SizedBox(height: 16),
                                      _SessionNoticeCard(
                                        message: state.loginInfoMessage!,
                                      ),
                                    ],
                                    const SizedBox(height: 22),
                                    _LoginField(
                                      controller: _identifier,
                                      label: 'EMAIL OU TÉLÉPHONE',
                                      hint: AppBrandConfig.resolvedLoginIdentifierHint,
                                      icon: Icons.badge_outlined,
                                      keyboardType: TextInputType.text,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      autocorrect: false,
                                      validator: _validateIdentifier,
                                    ),
                                    const SizedBox(height: 14),
                                    _LoginField(
                                      controller: _password,
                                      label: 'MOT DE PASSE',
                                      hint: '••••••••',
                                      icon: Icons.lock_outline_rounded,
                                      obscure: _obscure,
                                      trailing: IconButton(
                                        splashRadius: 20,
                                        iconSize: 20,
                                        color: AppColors.muted,
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                      ),
                                      validator: validateAppPassword,
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () =>
                                            ctx.push('/forgot-password'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                        ),
                                        child: const Text(
                                          'Mot de passe oublié ?',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 54,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          gradient: AppColors.clientCtaGradient,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.leaderGreen
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 18,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: loading
                                                ? null
                                                : () {
                                                    if (_formKey.currentState!
                                                        .validate()) {
                                                      ctx.read<AuthBloc>().add(
                                                        AuthLoginRequested(
                                                          identifier:
                                                              _identifier.text
                                                                  .trim(),
                                                          password:
                                                              _password.text,
                                                        ),
                                                      );
                                                    }
                                                  },
                                            child: Center(
                                            child: loading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2.4,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : const Text(
                                                      'Se connecter',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    Center(
                                      child: GestureDetector(
                                        onTap: () => ctx.go('/register'),
                                        child: RichText(
                                          text: const TextSpan(
                                            text: 'Pas encore de compte ? ',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.muted,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: "S'inscrire",
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ), // Column form
                              ), // Form
                            ), // Panel
                          ), // ConstrainedBox
                        ), // Center
                      ), // ScrollView
                    ), // Expanded
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Message utilisateur après fin de session (sans jargon technique).
class _SessionNoticeCard extends StatelessWidget {
  const _SessionNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.primary.withValues(alpha: 0.14)
        : AppColors.primary.withValues(alpha: 0.09);
    final border = AppColors.primary.withValues(alpha: 0.28);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 22,
              color: AppColors.primary.withValues(alpha: isDark ? 1.0 : 0.92),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                AppColors.leaderGreen,
                AppColors.accentTeal,
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Identifiants',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppBrandConfig.resolvedLoginFooterNote,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Carte de formulaire : surface claire et ombre douce.
class _PremiumLoginPanel extends StatelessWidget {
  const _PremiumLoginPanel({required this.child});
  final Widget child;

  static const double _r = 24.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_r),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: AppColors.leaderGreen.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 22),
            spreadRadius: -14,
          ),
          BoxShadow(
            color: const Color(0xFF0B1220).withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        child: child,
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.trailing,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final Widget? trailing;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          autocorrect: autocorrect,
          validator: validator,
          style: const TextStyle(
            fontSize: 15.5,
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Icon(icon, size: 20, color: AppColors.muted),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: trailing,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
            filled: true,
            fillColor: AppColors.successSurface.withValues(alpha: 0.55),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.line.withValues(alpha: 0.65),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.line.withValues(alpha: 0.65),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
