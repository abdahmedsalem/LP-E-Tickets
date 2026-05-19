import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/otp_remote_service.dart';
import '../../../shared/widgets/app_status_lottie.dart';

class ForgotOtpRouteArgs {
  const ForgotOtpRouteArgs({
    required this.identifier,
    required this.channel,
  });

  /// Email ou téléphone complet +222xxxxxxxx
  final String identifier;
  final OtpChannel channel;
}

/// Après vérification OTP : identifiant et code pour la réinitialisation du mot de passe.
class ForgotResetRouteArgs {
  const ForgotResetRouteArgs({
    required this.identifier,
    required this.otpCode,
  });

  final String identifier;
  final String otpCode;
}

class ForgotVerifyOtpScreen extends StatefulWidget {
  const ForgotVerifyOtpScreen({super.key, required this.args});

  final ForgotOtpRouteArgs args;

  @override
  State<ForgotVerifyOtpScreen> createState() => _ForgotVerifyOtpScreenState();
}

class _ForgotVerifyOtpScreenState extends State<ForgotVerifyOtpScreen> {
  final _otp = TextEditingController();
  final _otpService = OtpRemoteService();
  bool _busy = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length < 4 || clean.length > 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saisissez le code (4 à 6 chiffres selon le canal).'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _otpService.verifyOtp(
        identifier: widget.args.identifier,
        code: clean,
      );
      if (!mounted) return;
      context.push(
        '/forgot-password/reset',
        extra: ForgotResetRouteArgs(
          identifier: widget.args.identifier,
          otpCode: clean,
        ),
      );
    } on OtpException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Code de vérification',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const AppInlineLoading(size: 22)
                        : const Text('Continuer'),
                  ),
                ),
              ],
            ),
          ),
        ),
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

class _ResetPasswordAfterOtpScreenState extends State<ResetPasswordAfterOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _otpService = OtpRemoteService();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _otpService.resetPassword(
        identifier: widget.args.identifier,
        otpCode: widget.args.otpCode,
        newPassword: _pass.text,
      );
      await AuthRepository.instance.syncLocalPasswordIfExists(
        identifier: widget.args.identifier,
        newPassword: _pass.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe mis à jour. Connectez-vous.')),
      );
      context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Nouveau mot de passe',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _pass,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Mot de passe (6 chiffres)',
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: validateSixDigitNumericPassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pass2,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Confirmer (6 chiffres)',
                      counterText: '',
                    ),
                    validator: (v) {
                      final err = validateSixDigitNumericPassword(v);
                      if (err != null) return err;
                      if (v != _pass.text) {
                        return 'Les mots de passe ne correspondent pas.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const AppInlineLoading(size: 22)
                          : const Text('Enregistrer'),
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
