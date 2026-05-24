import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/config/app_brand_config.dart';
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
    _identifier.addListener(_onFieldChanged);
    _password.addListener(_onFieldChanged);
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
    _identifier.removeListener(_onFieldChanged);
    _password.removeListener(_onFieldChanged);
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showContactsHelp() async {
    if (!mounted) return;
    await showAppAlertDialog(
      context,
      title: 'Contacts',
      message:
          'Contactez votre support FuelToken ou votre point de contact habituel pour obtenir de l’aide.',
      confirmLabel: 'Fermer',
      icon: Icons.mail_outline_rounded,
    );
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
        backgroundColor: Colors.white,
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
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 4),
                            const _LoginBrandBlock(),
                            const SizedBox(height: 44),
                            const _LoginWelcomeCopy(),
                            const SizedBox(height: 34),
                            const _LoginSectionTitle(title: 'Connexion'),
                            const SizedBox(height: 16),
                            _LoginTextField(
                              controller: _identifier,
                              hint: AppBrandConfig.resolvedLoginIdentifierHint,
                              obscure: false,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.none,
                              autocorrect: false,
                              validator: _validateIdentifier,
                              borderColor: const Color(0xFFC7CEDA),
                              counterLabel: _identifier.text.trim().isEmpty
                                  ? '0/8'
                                  : '${_identifier.text.trim().length}/8',
                            ),
                            const SizedBox(height: 18),
                            _LoginTextField(
                              controller: _password,
                              hint: 'Mot de passe',
                              obscure: _obscure,
                              validator: validateAppPassword,
                              borderColor: const Color(0xFFC7CEDA),
                              counterLabel:
                                  '${_password.text.trim().length}/4',
                              trailing: IconButton(
                                splashRadius: 20,
                                iconSize: 20,
                                color: const Color(0xFF7A8798),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscure = !_obscure,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => ctx.push('/forgot-password'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF203A73),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Mot de passe oublié ?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 56,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF065F46),
                                      Color(0xFF2EA043),
                                      Color(0xFF34D399),
                                    ],
                                    stops: [0.0, 0.48, 1.0],
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: loading
                                        ? null
                                        : () {
                                            if (_formKey.currentState!
                                                .validate()) {
                                              ctx.read<AuthBloc>().add(
                                                AuthLoginRequested(
                                                  identifier: _identifier.text
                                                      .trim(),
                                                  password: _password.text,
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
                                              'Connexion',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  const Text(
                                    'Nouvel utilisateur ?',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => ctx.go('/register'),
                                    child: const Text(
                                      "S'inscrire maintenant",
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: Color(0xFF203A73),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: Color(0xFF203A73),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            Center(
                              child: SizedBox(
                                width: 212,
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: _showContactsHelp,
                                  icon: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 19,
                                    color: Color(0xFF203A73),
                                  ),
                                  label: const Text(
                                    'Contacts',
                                    style: TextStyle(
                                      fontSize: 15.2,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF203A73),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0xFF203A73),
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            if (state.loginInfoMessage != null) ...[
                              const SizedBox(height: 18),
                              _SessionNoticeCard(message: state.loginInfoMessage!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 22,
              color: Color(0xFF203A73),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBrandBlock extends StatelessWidget {
  const _LoginBrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_fueltoken.png',
              width: 86,
              height: 86,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                _FuelTokenWordmark(),
                SizedBox(height: 0),
                Text(
                  'SMART FUEL WALLET',
                  style: TextStyle(
                    fontSize: 10.0,
                    letterSpacing: 4.6,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _FuelTokenWordmark extends StatelessWidget {
  const _FuelTokenWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'Fuel',
            style: TextStyle(
              color: Color(0xFF203A73),
              fontSize: 34,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          TextSpan(
            text: 'Token',
            style: TextStyle(
              color: Color(0xFF2EA043),
              fontSize: 34,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginWelcomeCopy extends StatelessWidget {
  const _LoginWelcomeCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Bienvenue dans votre',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            height: 1.18,
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w400,
            letterSpacing: -0.8,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'espace wallet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            height: 1.18,
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w400,
            letterSpacing: -0.8,
          ),
        ),
      ],
    );
  }
}

class _LoginSectionTitle extends StatelessWidget {
  const _LoginSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        color: Color(0xFF203A73),
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.hint,
    required this.validator,
    required this.borderColor,
    required this.counterLabel,
    this.trailing,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final Color borderColor;
  final String counterLabel;
  final Widget? trailing;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          autocorrect: autocorrect,
          validator: validator,
          style: const TextStyle(
            fontSize: 15.5,
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 15.5,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            suffixIcon: trailing,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor, width: 1.1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor, width: 1.1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFF203A73), width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            counterLabel,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.1,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
