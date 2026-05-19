import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/odoo_api_config.dart';
import '../../../core/config/odoo_auth_rpc_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/models/user_role.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../data/services/otp_remote_service.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../bloc/auth_bloc.dart';
import 'signup_pending_screen.dart';

/// Arguments [GoRoute.extra] pour `/register/verify-otp`.
class RegisterOtpRouteArgs {
  const RegisterOtpRouteArgs({
    required this.email,
    required this.name,
    required this.phoneFull,
    required this.password,
    required this.channel,
  });

  final String email;
  final String name;
  final String phoneFull;
  final String password;
  final OtpChannel channel;
}

class RegisterVerifyOtpScreen extends StatefulWidget {
  const RegisterVerifyOtpScreen({super.key, required this.args});

  final RegisterOtpRouteArgs args;

  @override
  State<RegisterVerifyOtpScreen> createState() =>
      _RegisterVerifyOtpScreenState();
}

class _RegisterVerifyOtpScreenState extends State<RegisterVerifyOtpScreen> {
  final _otp = TextEditingController();
  final _otpService = OtpRemoteService();
  bool _busy = false;
  bool _resendBusy = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  String get _verifyIdentifier => widget.args.channel == OtpChannel.email
      ? widget.args.email.trim()
      : widget.args.phoneFull;

  bool get _acpecSignupAfterOtp =>
      OdooApiConfig.isConfigured && OdooAuthRpcConfig.hasCompleteRegistration;

  Future<void> _submit() async {
    final pwdErr = validateSixDigitNumericPassword(widget.args.password);
    if (pwdErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pwdErr)));
      return;
    }
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
        identifier: _verifyIdentifier,
        code: clean,
      );
      if (_acpecSignupAfterOtp) {
        await OdooAuthService.instance.submitSignupAfterOtp(
          email: widget.args.email.trim(),
          phoneFull: widget.args.phoneFull,
          password: widget.args.password,
          fullName: widget.args.name.trim(),
          otpCode: clean,
        );
        if (!mounted) return;
        context.go(
          '/signup/pending',
          extra: SignupPendingRouteArgs(
            identifier: widget.args.email.trim(),
            password: widget.args.password,
          ),
        );
        return;
      }
      final body = await _otpService.completeRegistration(
        email: widget.args.email.trim(),
        phoneFull: widget.args.phoneFull,
        password: widget.args.password,
        fullName: widget.args.name.trim(),
      );
      final user = _otpService.userFromCompleteRegistration(body);
      Map<String, dynamic>? tok;
      final t = body['tokens'];
      if (t is Map) {
        tok = Map<String, dynamic>.from(t);
      }
      if (!mounted) return;
      context.read<AuthBloc>().add(
            AuthRemoteRegistrationCompleted(
              user: user,
              password: widget.args.password,
              tokens: tok,
            ),
          );
    } on OtpException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resendBusy = true);
    try {
      await _otpService.sendRegistrationOtp(
        channel: widget.args.channel,
        email: widget.args.email.trim(),
        name: widget.args.name.trim(),
        phoneFull: widget.args.phoneFull,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Un nouveau code a été demandé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dest = widget.args.channel == OtpChannel.email
        ? widget.args.email
        : widget.args.phoneFull;

    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(state.errorMessage!)),
              );
            }
            if (state.status == AuthStatus.authenticated && state.user != null) {
              final path = switch (state.user!.role) {
                UserRole.admin => '/admin',
                UserRole.station => '/station',
                UserRole.user => '/home',
              };
              context.go(path);
            }
          },
          builder: (ctx, state) {
            final loggingIn = state.status == AuthStatus.authenticating;
            return Column(
              children: [
                AppBarHeader(
                  title: 'Vérification',
                  subtitle: 'Code de vérification',
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            Icon(
                              widget.args.channel == OtpChannel.email
                                  ? Icons.mark_email_unread_outlined
                                  : Icons.sms_outlined,
                              size: 48,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Entrez le code reçu',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _acpecSignupAfterOtp
                                  ? 'Code envoyé à :\n$dest\n\n'
                                      'Saisissez-le ci-dessous pour finaliser votre demande. '
                                      'Un administrateur validera votre compte avant la connexion.'
                                  : 'Code envoyé à :\n$dest',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _otp,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 8,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '••••••',
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed:
                                    (_busy || loggingIn) ? null : _submit,
                                child: (_busy || loggingIn)
                                    ? const AppInlineLoading(size: 22)
                                    : Text(
                                        _acpecSignupAfterOtp
                                            ? 'Valider et envoyer la demande ACPEC'
                                            : 'Valider et ouvrir la session',
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed:
                                  _resendBusy ? null : _resend,
                              child: _resendBusy
                                  ? const AppInlineLoading(size: 20)
                                  : const Text('Renvoyer le code'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
