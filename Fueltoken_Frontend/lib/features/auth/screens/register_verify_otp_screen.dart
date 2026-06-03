import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_role.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../bloc/auth_bloc.dart';

/// Arguments [GoRouter.extra] pour `/register/verify-otp`.
class RegisterOtpRouteArgs {
  const RegisterOtpRouteArgs({
    required this.name,
    required this.phoneFull,
    required this.password,
    required this.challengeId,
  });

  final String name;
  final String phoneFull;
  final String password;
  final int challengeId;
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
  bool _busy = false;
  bool _resendBusy = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez un code à 6 chiffres.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final body = await OdooAuthService.instance.verifySignupOtp(
        identifier: widget.args.phoneFull,
        code: clean,
        challengeId: widget.args.challengeId,
      );
      final payload = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : Map<String, dynamic>.from(body as Map);
      final user = AppUser.fromOdooProfileMap(payload, envelope: body);
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthSessionEstablished(user));
      if (!mounted) return;
      final path = switch (user.role) {
        UserRole.admin => '/admin',
        UserRole.station => '/station',
        UserRole.user => '/home',
      };
      context.go(path);
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

  Future<void> _resend() async {
    setState(() => _resendBusy = true);
    try {
      await OdooAuthService.instance.requestSignupOtpResend(
        identifier: widget.args.phoneFull,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Un nouveau code a été demandé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dest = localMrDigitsFromFull(widget.args.phoneFull);

    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            }
            if (state.status == AuthStatus.authenticated &&
                state.user != null) {
              final path = switch (state.user!.role) {
                UserRole.admin => '/admin',
                UserRole.station => '/station',
                UserRole.user => '/home',
              };
              context.go(path);
            }
          },
          builder: (ctx, state) {
            return Column(
              children: [
                AppBarHeader(
                  title: 'Vérification',
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
                            const Icon(
                              Icons.sms_outlined,
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
                              'Code envoyé à :\n$dest\n\n'
                              'Saisissez-le ci-dessous pour finaliser votre inscription.',
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
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Vérifier'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _resendBusy ? null : _resend,
                              child: _resendBusy
                                  ? const Text('Demande en cours...')
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
