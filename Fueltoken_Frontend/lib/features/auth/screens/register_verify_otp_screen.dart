import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/pending_signup_store.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_role.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../core/utils/error_presenter.dart';
import '../bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

/// Arguments [GoRouter.extra] pour `/register/verify-otp`.
class RegisterOtpRouteArgs {
  const RegisterOtpRouteArgs({
    required this.name,
    required this.phoneFull,
    this.pin = '',
    required this.companyId,
    this.challengeId,
  });

  final String name;
  final String phoneFull;
  final String pin;
  final int companyId;
  final int? challengeId;
}

class RegisterVerifyOtpScreen extends StatefulWidget {
  const RegisterVerifyOtpScreen({super.key, this.args});

  final RegisterOtpRouteArgs? args;

  @override
  State<RegisterVerifyOtpScreen> createState() =>
      _RegisterVerifyOtpScreenState();
}

class _RegisterVerifyOtpScreenState extends State<RegisterVerifyOtpScreen> {
  final _otp = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _resendBusy = false;
  bool _loadingPending = false;
  int? _challengeId;
  RegisterOtpRouteArgs? _args;

  @override
  void initState() {
    super.initState();
    _args = widget.args;
    _challengeId = _args?.challengeId;
    if (_args == null) {
      _loadingPending = true;
      _loadPendingSignup();
    }
  }

  @override
  void dispose() {
    _otp.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _loadPendingSignup() async {
    final pending = await PendingSignupStore.loadUsable();
    if (!mounted) return;
    setState(() {
      _loadingPending = false;
      if (pending != null) {
        _args = RegisterOtpRouteArgs(
          name: pending.name,
          phoneFull: pending.phoneFull,
          companyId: pending.companyId,
          challengeId: pending.challengeId,
        );
        _challengeId = pending.challengeId;
      }
    });
  }

  bool get _needsPinEntry => (_args?.pin.trim().isEmpty ?? true);

  String get _pinForSubmit {
    final fromArgs = _args?.pin.trim() ?? '';
    if (fromArgs.isNotEmpty) return fromArgs;
    return _pin.text.trim();
  }

  Future<void> _submit() async {
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != kOtpSmsCodeLength) {
      AppMessage.error(
        context,
        'Saisissez un code à $kOtpSmsCodeLength chiffres.',
      );
      return;
    }
    final args = _args;
    if (args == null) {
      AppMessage.error(
        context,
        'Code SMS introuvable, expiré ou déjà utilisé. Recommencez l’inscription.',
      );
      return;
    }
    final pin = _pinForSubmit;
    if (validateFourDigitNumericPassword(pin) != null) {
      AppMessage.error(context, 'Saisissez votre PIN à 4 chiffres.');
      return;
    }

    setState(() => _busy = true);
    try {
      final body = await OdooAuthService.instance.verifySignupOtp(
        identifier: args.phoneFull,
        code: clean,
        name: args.name,
        pin: pin,
        companyId: args.companyId,
        challengeId: _challengeId,
      );
      final payload = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : Map<String, dynamic>.from(body as Map);
      final user = AppUser.fromOdooProfileMap(payload, envelope: body);
      final tokens = _extractTokens(body);
      final hasTokens = _hasSessionTokens(tokens);

      if (!hasTokens) {
        throw Exception(
          'Inscription incomplète : session mobile absente. '
          'Réessayez ou contactez l’administrateur.',
        );
      }

      await PendingSignupStore.clear();
      if (!mounted) return;
      context.read<AuthBloc>().add(
        AuthRemoteRegistrationCompleted(user: user, pin: pin, tokens: tokens),
      );
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SMS verification failed: ${e.runtimeType}\n$st');
      }
      if (mounted) {
        AppMessage.error(context, _displayOtpVerificationError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayOtpVerificationError(Object error) {
    if (error is OdooJsonRpcException) {
      final code = error.publicCode?.trim().toUpperCase();
      final ref = error.reference?.trim();
      if (code == 'AUTH_REFUSED' ||
          code == 'REQUEST_REFUSED' ||
          code == 'VALIDATION_ERROR') {
        final suffix = ref != null && ref.isNotEmpty
            ? '\nRéférence support : $ref'
            : '';
        return 'Code SMS introuvable, expiré ou déjà utilisé. '
            'Demandez un nouveau code puis réessayez.$suffix';
      }
    }
    return ErrorPresenter.message(error);
  }

  bool _hasSessionTokens(Map<String, dynamic>? tokens) {
    final access = tokens?['access']?.toString().trim() ?? '';
    final refresh = tokens?['refresh']?.toString().trim() ?? '';
    return access.isNotEmpty && refresh.isNotEmpty;
  }

  Map<String, dynamic>? _extractTokens(Map<String, dynamic> body) {
    Map<String, dynamic>? pick(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final top = pick(body);
    if (top == null) return null;

    final candidates = <Map<String, dynamic>>[
      top,
      if (top['data'] is Map) Map<String, dynamic>.from(top['data'] as Map),
      if (top['user'] is Map) Map<String, dynamic>.from(top['user'] as Map),
    ];

    for (final map in candidates) {
      final access =
          map['access_token']?.toString().trim() ??
          map['ACCESS_TOKEN']?.toString().trim() ??
          map['accessToken']?.toString().trim() ??
          '';
      final refresh =
          map['refresh_token']?.toString().trim() ??
          map['REFRESH_TOKEN']?.toString().trim() ??
          map['refreshToken']?.toString().trim() ??
          '';
      if (access.isNotEmpty || refresh.isNotEmpty) {
        return <String, dynamic>{
          if (access.isNotEmpty) 'access': access,
          if (refresh.isNotEmpty) 'refresh': refresh,
        };
      }
    }
    return null;
  }

  Future<void> _leaveVerification() async {
    await PendingSignupStore.clear();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/register');
  }

  Future<void> _resend() async {
    final args = _args;
    if (args == null) {
      AppMessage.error(
        context,
        'Recommencez l’inscription pour demander un nouveau code.',
      );
      return;
    }
    setState(() => _resendBusy = true);
    try {
      final response = await OdooAuthService.instance.requestSignupOtpResend(
        identifier: args.phoneFull,
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
          await PendingSignupStore.save(
            name: args.name,
            phoneFull: args.phoneFull,
            challengeId: parsed,
            companyId: args.companyId,
          );
        }
      }
      if (mounted) {
        AppMessage.info(context, 'Un nouveau code a été demandé.');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('OTP resend failed: ${e.runtimeType}\n$st');
      }
      if (mounted) {
        AppMessage.error(context, ErrorPresenter.message(e));
      }
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPending) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final args = _args;
    if (args == null) {
      return const _MissingRegisterOtpScreen();
    }

    final dest = localMrDigitsFromFull(args.phoneFull);

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
                              onTap: _leaveVerification,
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
                          maxLength: kOtpSmsCodeLength,
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
                        if (_needsPinEntry) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _pin,
                            keyboardType: TextInputType.number,
                            maxLength: kSecretCodeLength,
                            obscureText: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'PIN de confirmation',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
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

class _MissingRegisterOtpScreen extends StatelessWidget {
  const _MissingRegisterOtpScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Code SMS introuvable',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Recommencez l’inscription pour recevoir un nouveau code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Recommencer l’inscription'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Retour connexion'),
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
