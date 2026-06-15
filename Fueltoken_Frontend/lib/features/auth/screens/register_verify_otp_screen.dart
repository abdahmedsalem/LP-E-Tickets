import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/validation/contact_validators.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_role.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

/// Arguments [GoRouter.extra] pour `/register/verify-otp`.
class RegisterOtpRouteArgs {
  const RegisterOtpRouteArgs({
    required this.name,
    required this.phoneFull,
    required this.password,
    this.challengeId,
  });

  final String name;
  final String phoneFull;
  final String password;
  final int? challengeId;
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

  Future<void> _submit() async {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != 6) {
      AppMessage.error(context, 'Saisissez un code à 6 chiffres.');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = await OdooAuthService.instance.verifySignupOtp(
        identifier: widget.args.phoneFull,
        code: clean,
        name: widget.args.name,
        password: widget.args.password,
        challengeId: _challengeId,
      );
      final payload = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : Map<String, dynamic>.from(body as Map);
      final user = AppUser.fromOdooProfileMap(payload, envelope: body);
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthSessionEstablished(user));
      return;
    } catch (e, st) {
      debugPrint('OTP verification failed: $e\n$st');
      if (mounted) {
        AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resendBusy = true);
    try {
      final response = await OdooAuthService.instance.requestSignupOtpResend(
        identifier: widget.args.phoneFull,
      );
      final data = response['data'];
      if (data is Map) {
        final raw =
            data['otp_challenge_id'] ??
            data['challenge_id'] ??
            response['otp_challenge_id'] ??
            response['challenge_id'];
        final parsed = int.tryParse(raw?.toString() ?? '');
        if (parsed != null && parsed > 0) {
          _challengeId = parsed;
        }
      }
      if (mounted) {
        AppMessage.info(context, 'Un nouveau code a été demandé.');
      }
    } catch (e, st) {
      debugPrint('OTP resend failed: $e\n$st');
      if (mounted) {
        AppMessage.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dest = localMrDigitsFromFull(widget.args.phoneFull);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null) {
              AppMessage.error(ctx, state.errorMessage!);
            }
            if (state.status == AuthStatus.authenticated &&
                state.user != null) {
              final path = switch (state.user!.role) {
                UserRole.admin => '/admin',
                UserRole.station => '/station',
                UserRole.user => '/home',
              };
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                context.go(path);
              });
            }
          },
          builder: (ctx, state) {
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
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
                              onTap: () => context.pop(),
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
                        const _OtpWelcomeCopy(),
                        const SizedBox(height: 34),
                        const _OtpSectionTitle(title: 'Vérification'),
                        const SizedBox(height: 16),
                        Text(
                          'Code envoyé à $dest',
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
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
                            color: Color(0xFF1E293B),
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '••••••',
                            hintStyle: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w700,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFC7CEDA),
                                width: 1.1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFC7CEDA),
                                width: 1.1,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(14),
                              ),
                              borderSide: BorderSide(
                                color: Color(0xFF203A73),
                                width: 1.6,
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
                                onTap: _busy ? null : _submit,
                                child: Center(
                                  child: _busy
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Vérifier',
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
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: _resendBusy ? null : _resend,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF203A73),
                            ),
                            child: _resendBusy
                                ? const Text('Demande en cours...')
                                : const Text('Renvoyer le code'),
                          ),
                        ),
                      ],
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

class _OtpWelcomeCopy extends StatelessWidget {
  const _OtpWelcomeCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Confirmez votre',
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
          'numéro mobile',
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

class _OtpSectionTitle extends StatelessWidget {
  const _OtpSectionTitle({required this.title});

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
