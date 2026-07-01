import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../shared/widgets/app_message.dart';

class ForgotOtpRouteArgs {
  const ForgotOtpRouteArgs({required this.identifier, this.challengeId});

  /// Telephone complet: +222xxxxxxxx.
  final String identifier;
  final int? challengeId;
}

class ForgotResetRouteArgs {
  const ForgotResetRouteArgs({required this.identifier});

  final String identifier;
}

class ForgotVerifyOtpScreen extends StatefulWidget {
  const ForgotVerifyOtpScreen({super.key, required this.args});

  final ForgotOtpRouteArgs args;

  @override
  State<ForgotVerifyOtpScreen> createState() => _ForgotVerifyOtpScreenState();
}

class _ForgotVerifyOtpScreenState extends State<ForgotVerifyOtpScreen> {
  final _otp = TextEditingController();
  bool _busy = false;
  int? _challengeId;

  @override
  void initState() {
    super.initState();
    _challengeId = widget.args.challengeId;
  }

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      final response = await OdooAuthService.instance.requestPasswordResetOtp(
        phoneFull: widget.args.identifier,
      );
      final data = response['data'];
      if (data is Map) {
        _challengeId = int.tryParse(data['otp_challenge_id']?.toString() ?? '');
      }
      if (mounted) {
        AppMessage.info(context, 'Code renvoye par SMS.');
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != kOtpSmsCodeLength) {
      if (mounted) {
        AppMessage.error(context, 'Saisissez le code OTP a 6 chiffres.');
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await OdooAuthService.instance.verifyPasswordResetOtp(
        identifier: widget.args.identifier,
        code: clean,
        challengeId: _challengeId,
      );
      if (!mounted) return;
      context.push(
        '/forgot-password/reset',
        extra: ForgotResetRouteArgs(identifier: widget.args.identifier),
      );
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ForgotFlowScaffold(
      onBack: () => context.pop(),
      title: 'Verification du code',
      subtitle: 'Saisissez le code recu par SMS.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OtpField(controller: _otp),
                const SizedBox(height: 18),
                _PrimaryActionButton(
                  label: 'Continuer',
                  busy: _busy,
                  onTap: _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Renvoyer le code'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ResetPasswordAfterOtpScreen extends StatefulWidget {
  const ResetPasswordAfterOtpScreen({super.key, required this.args});

  final ForgotResetRouteArgs args;

  @override
  State<ResetPasswordAfterOtpScreen> createState() =>
      _ResetPasswordAfterOtpScreenState();
}

class _ResetPasswordAfterOtpScreenState
    extends State<ResetPasswordAfterOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await AuthRepository.instance.resetPinForIdentifier(
        identifier: widget.args.identifier,
        newPin: _pass.text,
      );
      await AuthRepository.instance.syncLocalPinIfExists(
        identifier: widget.args.identifier,
        newPin: _pass.text,
      );
      if (!mounted) return;
      AppMessage.info(context, 'PIN mis a jour. Connectez-vous.');
      context.go('/login');
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ForgotFlowScaffold(
      onBack: () => context.pop(),
      title: 'Nouveau PIN',
      subtitle: 'Choisissez un PIN numerique a 4 chiffres.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PasswordField(
                    controller: _pass,
                    obscure: _obscure,
                    label: 'PIN',
                    hint: '4 chiffres',
                    trailing: IconButton(
                      splashRadius: 20,
                      iconSize: 20,
                      color: const Color(0xFF7A8798),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: validateFourDigitNumericPassword,
                  ),
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _pass2,
                    obscure: _obscure,
                    label: 'Confirmer',
                    hint: 'Ressaisir le PIN',
                    validator: (v) {
                      final err = validateFourDigitNumericPassword(v);
                      if (err != null) return err;
                      if (v != _pass.text) {
                        return 'Les PIN ne correspondent pas.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _PrimaryActionButton(
                    label: 'Enregistrer',
                    busy: _busy,
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForgotFlowScaffold extends StatelessWidget {
  const _ForgotFlowScaffold({
    required this.onBack,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final VoidCallback onBack;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: onBack,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                size: 22,
                                color: Color(0xFF203A73),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Image.asset(
                          'designs/lplogo.jfif',
                          height: 128,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0B1220),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: child,
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF065F46), Color(0xFF2EA043), Color(0xFF34D399)],
            stops: [0.0, 0.48, 1.0],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: kOtpSmsCodeLength,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: 6,
      ),
      decoration: InputDecoration(
        labelText: 'Code OTP',
        hintText: '------',
        counterText: '',
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onSubmitted: (_) {},
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.label,
    required this.hint,
    this.trailing,
    required this.validator,
  });

  final TextEditingController controller;
  final bool obscure;
  final String label;
  final String hint;
  final Widget? trailing;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: kSecretCodeLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        suffixIcon: trailing,
      ),
      validator: validator,
    );
  }
}
