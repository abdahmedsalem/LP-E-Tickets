import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/validation/password_validators.dart'
    show kOtpSmsCodeLength;
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/app_alert_dialog.dart';
import '../../../shared/widgets/auth_brand_image.dart';
import '../bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _otp = TextEditingController();

  bool _handlingAuthMessage = false;
  bool _otpStep = false;
  int? _challengeId;
  String? _otpIdentifier;

  @override
  void initState() {
    super.initState();
    _identifier.addListener(_onIdentifierChanged);
    _otp.addListener(_onFieldChanged);
    _hydrateIdentifier();
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
    _identifier.removeListener(_onIdentifierChanged);
    _otp.removeListener(_onFieldChanged);
    _identifier.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _onIdentifierChanged() {
    final current = _identifier.text.trim();
    if (_otpStep && _otpIdentifier != null && current != _otpIdentifier) {
      _otpStep = false;
      _challengeId = null;
      _otpIdentifier = null;
      _otp.clear();
    }
    if (mounted) setState(() {});
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  void _resetOtpStep() {
    setState(() {
      _otpStep = false;
      _challengeId = null;
      _otpIdentifier = null;
      _otp.clear();
    });
  }

  Future<void> _showContactsHelp() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await showAppAlertDialog(
      context,
      title: l10n.authContacts,
      message: l10n.authContactsHelp,
      confirmLabel: l10n.commonClose,
      icon: Icons.mail_outline_rounded,
    );
  }

  String _presentLoginFailure(String raw) {
    if (Localizations.localeOf(context).languageCode == 'ar') {
      return AppLocalizations.of(context).authLoginFailed;
    }
    final t = raw.trim();
    if (t.isEmpty) {
      return AppLocalizations.of(context).authLoginFailed;
    }
    // Erreurs JSON-RPC / réseau (souvent > 160 car.) : les afficher pour diagnostic
    // (ex. mauvaise ODOO_JSONRPC_BASE_URL depuis un téléphone).
    if (t.length > 900) {
      return '${t.substring(0, 900)}…';
    }
    return t;
  }

  String _presentOtpFailure(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return AppLocalizations.of(context).authOtpIncorrect;
    }

    final normalized = t.toLowerCase();
    if (normalized.contains('incorrect') ||
        normalized.contains('invalid') ||
        normalized.contains('pin incorrect') ||
        normalized.contains('code sms')) {
      return AppLocalizations.of(context).authOtpIncorrect;
    }

    return _presentLoginFailure(t);
  }

  String? _validateIdentifier(String? v) {
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) {
      return l10n.authPhoneRequired;
    }
    var digits = v.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('222')) {
      digits = digits.substring(3);
    }
    return digits.length == 8 ? null : l10n.authPhoneInvalid;
  }

  String? _validateOtp(String? v) {
    final clean = (v ?? '').trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != kOtpSmsCodeLength) {
      return AppLocalizations.of(context).authOtpLength(kOtpSmsCodeLength);
    }
    return null;
  }

  String get _phoneCounterLabel {
    final t = _identifier.text.trim();
    if (t.isEmpty) return AppLocalizations.of(context).authDigitsCount(8);
    var digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('222')) {
      digits = digits.substring(3);
    }
    return '${digits.length}/8';
  }

  String get _otpCounterLabel {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    return '${clean.length}/$kOtpSmsCodeLength';
  }

  String _presentLoginInfo(String raw) {
    if (Localizations.localeOf(context).languageCode == 'ar') {
      return AppLocalizations.of(context).sessionExpiredReconnect;
    }
    return raw;
  }

  void _submit(AuthState state) {
    if (!_formKey.currentState!.validate()) return;
    final authBloc = context.read<AuthBloc>();
    if (_otpStep) {
      authBloc.add(
        AuthLoginOtpVerified(
          identifier: _otpIdentifier ?? _identifier.text.trim(),
          code: _otp.text.trim().replaceAll(RegExp(r'\D'), ''),
          challengeId: _challengeId ?? state.loginOtpChallengeId,
        ),
      );
      return;
    }
    authBloc.add(AuthLoginOtpRequested(identifier: _identifier.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) =>
              a.status != b.status ||
              a.errorMessage != b.errorMessage ||
              a.loginInfoMessage != b.loginInfoMessage ||
              a.loginOtpChallengeId != b.loginOtpChallengeId ||
              a.loginOtpIdentifier != b.loginOtpIdentifier,
          listener: (ctx, state) async {
            if (state.status == AuthStatus.unauthenticated &&
                state.loginOtpIdentifier != null) {
               final id = state.loginOtpIdentifier!.trim();
               if (ctx.mounted) {
                 setState(() {
                  _otpStep = true;
                  _otpIdentifier = id;
                  _challengeId = state.loginOtpChallengeId;
                  _otp.clear();
                });
              }
            }
            if (state.status == AuthStatus.authenticated) {
              // La navigation après connexion est gérée par [AppRouter] via
              // `redirect` (`loggedIn && atAuthRoute` → `/home` | `/station`).
              // Ne pas utiliser GoRouterState.of / ctx.go ici : après un await, le
              // contexte du listener peut ne plus être sous le RouteMatch (GoError).
            }
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null &&
                !_handlingAuthMessage) {
              _handlingAuthMessage = true;
              final msg = _otpStep
                  ? _presentOtpFailure(state.errorMessage!)
                  : _presentLoginFailure(state.errorMessage!);
              if (ctx.mounted) {
                if (_otpStep) {
                  AppMessage.error(ctx, msg);
                } else {
                  await showAppAlertDialog(
                    ctx,
                    title: l10n.authLoginTitle,
                    message: msg,
                    confirmLabel: l10n.commonClose,
                    isError: true,
                    icon: Icons.gpp_maybe_outlined,
                  );
                }
              }
              _handlingAuthMessage = false;
            }
          },
          builder: (ctx, state) {
            final loading = state.status == AuthStatus.authenticating;
            final buttonLabel = _otpStep ? l10n.authContinue : l10n.authSignIn;
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
                              const SizedBox(height: 16),
                              const AuthBrandImage(),
                              SizedBox(height: _otpStep ? 10 : 34),
                                        _LoginSectionTitle(
                                          title: _otpStep
                                              ? l10n.authVerificationCode
                                              : l10n.authAccountVerification,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _otpStep
                                              ? l10n.authOtpSentTo(
                                                  _otpIdentifier ??
                                                      _identifier.text.trim(),
                                                )
                                              : l10n.authEnterPhone,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            height: 1.35,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _LoginTextField(
                                          controller: _identifier,
                                          hint: l10n.authPhone,
                                          obscure: false,
                                          keyboardType: TextInputType.phone,
                                          textCapitalization:
                                              TextCapitalization.none,
                                          autocorrect: false,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(8),
                                          ],
                                          validator: _validateIdentifier,
                                          borderColor: const Color(0xFFC7CEDA),
                                          counterLabel: _phoneCounterLabel,
                                        ),
                                        if (_otpStep) ...[
                                          const SizedBox(height: 18),
                                          _LoginTextField(
                                            controller: _otp,
                                            hint: l10n.authSmsCode,
                                            obscure: false,
                                            validator: _validateOtp,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                kOtpSmsCodeLength,
                                              ),
                                            ],
                                            borderColor: const Color(
                                              0xFFC7CEDA,
                                            ),
                                            counterLabel: _otpCounterLabel,
                                          ),
                                          Align(
                                            alignment:
                                                AlignmentDirectional.centerEnd,
                                            child: TextButton(
                                              onPressed: loading
                                                  ? null
                                                  : () {
                                                      _otp.clear();
                                                      ctx.read<AuthBloc>().add(
                                                        AuthLoginOtpRequested(
                                                          identifier:
                                                              _identifier.text
                                                                  .trim(),
                                                        ),
                                                      );
                                                    },
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFF203A73,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: Text(
                                                l10n.authResendCode,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          height: 56,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: loading
                                                    ? null
                                                    : () => _submit(state),
                                                child: Center(
                                                  child: loading
                                                      ? const SizedBox(
                                                          width: 24,
                                                          height: 24,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth:
                                                                    2.4,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        )
                                                      : Text(
                                                          buttonLabel,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_otpStep) ...[
                                          const SizedBox(height: 10),
                                          Center(
                                            child: TextButton(
                                              onPressed: loading
                                                  ? null
                                                  : _resetOtpStep,
                                              child: Text(l10n.authChangePhone),
                                            ),
                                          ),
                                        ],
                                        SizedBox(
                                          height: _otpStep ? 8 : 24,
                                        ),
                                        Center(
                                          child: Wrap(
                                            alignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 16,
                                            runSpacing: 8,
                                            children: [
                                              TextButton(
                                                onPressed: () => ctx.push(
                                                  '/forgot-password',
                                                ),
                                                child: Text(l10n.authForgotPin),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    ctx.go('/register'),
                                                child: Text(
                                                  l10n.authCreateAnAccount,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 18),
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
                                              label: Text(
                                                l10n.authContacts,
                                                style: const TextStyle(
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
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                backgroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (state.loginInfoMessage != null) ...[
                                          const SizedBox(height: 18),
                                          _SessionNoticeCard(
                                            message: _presentLoginInfo(
                                              state.loginInfoMessage!,
                                            ),
                                          ),
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

class _LoginSectionTitle extends StatelessWidget {
  const _LoginSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
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
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final Color borderColor;
  final String counterLabel;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
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
              borderSide: const BorderSide(
                color: Color(0xFFDC2626),
                width: 1.2,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFDC2626),
                width: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Align(
          alignment: AlignmentDirectional.centerEnd,
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
