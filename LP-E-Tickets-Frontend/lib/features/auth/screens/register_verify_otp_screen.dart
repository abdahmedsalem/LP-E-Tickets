import 'dart:async';
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
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/auth_brand_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/fuel_mark.dart';
import '../bloc/auth_bloc.dart';

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

  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _args = widget.args;
    _challengeId = _args?.challengeId;
    _otp.addListener(_onOtpChanged);
    if (_args == null) {
      _loadingPending = true;
      _loadPendingSignup();
    } else {
      _startOtpTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otp.removeListener(_onOtpChanged);
    _otp.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _onOtpChanged() {
    if (mounted) setState(() {});
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
        _startOtpTimer();
      }
    });
  }

  void _startOtpTimer() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = 300);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
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
    final l10n = AppLocalizations.of(context);
    final clean = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (clean.length != kOtpSmsCodeLength) {
      AppMessage.error(
        context,
        AppLocalizations.of(context).authOtpLength(kOtpSmsCodeLength),
      );
      return;
    }
    final args = _args;
    if (args == null) {
      AppMessage.error(
        context,
        AppLocalizations.of(context).authOtpMissingExpired,
      );
      return;
    }
    final pin = _pinForSubmit;
    if (validateFourDigitNumericPassword(pin) != null) {
      AppMessage.error(
        context,
        AppLocalizations.of(context).authEnterPinFourDigits,
      );
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
        throw Exception(l10n.authRegistrationIncomplete);
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
    final l10n = AppLocalizations.of(context);
    final raw = error.toString();
    if (raw.contains(l10n.authRegistrationIncomplete)) {
      return l10n.authRegistrationIncomplete;
    }
    if (ErrorPresenter.isBackendUnavailable(error)) {
      return l10n.commonServerUnavailable;
    }
    if (error is OdooJsonRpcException) {
      final code = error.publicCode?.trim().toUpperCase();
      if (code == 'RATE_LIMITED' || code == 'ACTION_CODE_LOCKED') {
        return l10n.commonTooManyAttempts;
      }
      if (code == 'SIGNUP_NOT_ALLOWED') {
        return l10n.authRegistrationFailed;
      }
      return l10n.authOtpMissingExpired;
    }
    return l10n.authOtpMissingExpired;
  }

  String _displayOtpResendError(Object error) {
    final l10n = AppLocalizations.of(context);
    if (ErrorPresenter.isBackendUnavailable(error)) {
      return l10n.commonServerUnavailable;
    }
    if (error is OdooJsonRpcException) {
      final code = error.publicCode?.trim().toUpperCase();
      if (code == 'RATE_LIMITED' || code == 'ACTION_CODE_LOCKED') {
        return l10n.commonTooManyAttempts;
      }
    }
    return l10n.authRestartToRequestCode;
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
    context.go('/register');
  }

  Future<void> _resend() async {
    final args = _args;
    if (args == null) {
      AppMessage.error(
        context,
        AppLocalizations.of(context).authRestartToRequestCode,
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
        _startOtpTimer();
        AppMessage.info(
          context,
          AppLocalizations.of(context).authNewCodeRequested,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('OTP resend failed: ${e.runtimeType}\n$st');
      }
      if (mounted) {
        AppMessage.error(context, _displayOtpResendError(e));
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
    final l10n = AppLocalizations.of(context);
    final step5Valid = _otp.text.length == 6;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null) {
              AppMessage.error(
                ctx,
                AppLocalizations.of(ctx).authRegistrationFailed,
              );
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
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                isAr
                                    ? Icons.arrow_forward_rounded
                                    : Icons.arrow_back_rounded,
                                color: const Color(0xFFD9A036),
                                size: 26,
                              ),
                              onPressed: _leaveVerification,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.authRegisterTitle,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        _StepItem(
                          stepNumber: 1,
                          title: l10n.authFullName,
                          isActive: false,
                          isCompleted: true,
                          isLast: false,
                          child: const SizedBox.shrink(),
                        ),
                        _StepItem(
                          stepNumber: 2,
                          title: l10n.authPhone,
                          isActive: false,
                          isCompleted: true,
                          isLast: false,
                          child: const SizedBox.shrink(),
                        ),
                        _StepItem(
                          stepNumber: 3,
                          title: l10n.authDefinePin,
                          isActive: false,
                          isCompleted: true,
                          isLast: false,
                          child: const SizedBox.shrink(),
                        ),
                        _StepItem(
                          stepNumber: 4,
                          title: l10n.authConfirmPin,
                          isActive: false,
                          isCompleted: true,
                          isLast: false,
                          child: const SizedBox.shrink(),
                        ),
                        _StepItem(
                          stepNumber: 5,
                          title: l10n.authVerificationCode,
                          isActive: true,
                          isCompleted: false,
                          isLast: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.authCodeSentShort(dest),
                                textAlign: TextAlign.start,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _OtpTimerWidget(
                                secondsRemaining: _secondsRemaining,
                                onResend: _resend,
                                resending: _resendBusy,
                              ),
                              const SizedBox(height: 24),
                              _OtpInputWidget(
                                controller: _otp,
                                length: 6,
                                onChanged: (_) {
                                  if (mounted) setState(() {});
                                },
                              ),
                              if (_needsPinEntry) ...[
                                const SizedBox(height: 14),
                                _RegisterField(
                                  controller: _pin,
                                  hint: l10n.authConfirmPin,
                                  validator: (value) =>
                                      validateFourDigitNumericPassword(value) ==
                                          null
                                      ? null
                                      : l10n.authEnterPinFourDigits,
                                  obscure: true,
                                  keyboardType: TextInputType.number,
                                  maxLength: kSecretCodeLength,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ],
                              const SizedBox(height: 28),
                              _StepNextButton(
                                onPressed: step5Valid && !_busy
                                    ? _submit
                                    : null,
                                loading: _busy,
                                label: l10n.authVerify,
                              ),
                            ],
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
    final l10n = AppLocalizations.of(context);
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
                  const AuthBrandImage(),
                  const SizedBox(height: 10),
                  Text(
                    l10n.authOtpMissing,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.authRestartRegistrationMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/register'),
                    child: Text(l10n.authRestartRegistration),
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(l10n.authBackToLogin),
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

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.stepNumber,
    required this.title,
    required this.isActive,
    required this.isCompleted,
    required this.isLast,
    required this.child,
  });

  final int stepNumber;
  final String title;
  final bool isActive;
  final bool isCompleted;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final circleColor = isCompleted
        ? const Color(0xFF94A3B8)
        : isActive
        ? theme.colorScheme.primary
        : const Color(0xFFCBD5E1);

    final circleChild = isCompleted
        ? const Icon(Icons.check, size: 14, color: Colors.white)
        : Text(
            '$stepNumber',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isActive ? Colors.white : const Color(0xFF64748B),
            ),
          );

    final titleStyle = TextStyle(
      fontSize: 14.5,
      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
      color: isActive
          ? const Color(0xFF0F172A)
          : isCompleted
          ? const Color(0xFF64748B)
          : const Color(0xFF94A3B8),
    );

    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isAr) ...[
          _buildIndicatorColumn(circleColor, circleChild, showConnector: true),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(title, style: titleStyle),
              if (isActive) ...[
                const SizedBox(height: 12),
                child,
                const SizedBox(height: 18),
              ] else ...[
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
        if (isAr) ...[
          const SizedBox(width: 14),
          _buildIndicatorColumn(circleColor, circleChild, showConnector: false),
        ],
      ],
    );
  }

  Widget _buildIndicatorColumn(
    Color circleColor,
    Widget circleChild, {
    required bool showConnector,
  }) {
    final lineHeight = isActive ? 36.0 : 24.0;
    return SizedBox(
      width: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: circleChild),
            ),
          ),
          if (!isLast && showConnector)
            SizedBox(
              height: lineHeight,
              child: const VerticalDivider(
                width: 2,
                thickness: 2,
                color: Color(0xFFCBD5E1),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepNextButton extends StatelessWidget {
  const _StepNextButton({
    required this.onPressed,
    required this.label,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF065F46),
                    Color(0xFF2EA043),
                    Color(0xFF34D399),
                  ],
                  stops: [0.0, 0.48, 1.0],
                )
              : null,
          color: enabled ? null : const Color(0xFFCBD5E1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Center(
                child: loading
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: enabled
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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

class _OtpInputWidget extends StatefulWidget {
  const _OtpInputWidget({
    required this.controller,
    required this.length,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String> onChanged;

  @override
  State<_OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<_OtpInputWidget> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                onChanged: widget.onChanged,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusNode.requestFocus();
            },
            child: Row(
              textDirection: TextDirection.ltr,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(widget.length, (index) {
                final text = widget.controller.text;
                final char = text.length > index ? text[index] : '';
                final isFocused = _focusNode.hasFocus && text.length == index;

                return Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: isFocused
                          ? AppColors.brandBlueDeep
                          : AppColors.leaderGreen,
                      width: isFocused ? 2.0 : 1.3,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    char,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpTimerWidget extends StatelessWidget {
  const _OtpTimerWidget({
    required this.secondsRemaining,
    required this.onResend,
    required this.resending,
  });

  final int secondsRemaining;
  final VoidCallback? onResend;
  final bool resending;

  @override
  Widget build(BuildContext context) {
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final progress = secondsRemaining / 300.0;

    return Column(
      children: [
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4.5,
                  backgroundColor: const Color(0xFFF5EFE6),
                  color: const Color(0xFF203A73),
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (secondsRemaining == 0)
          Center(
            child: TextButton(
              onPressed: resending ? null : onResend,
              child: resending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandBlue,
                      ),
                    )
                  : const Text(
                      'Renvoyer le code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF203A73),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _RegisterField extends StatelessWidget {
  const _RegisterField({
    required this.controller,
    required this.hint,
    required this.validator,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
    this.trailing,
    this.counterLabel = '',
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? trailing;
  final String counterLabel;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          validator: validator,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: const TextStyle(
            fontSize: 15.5,
            color: AppColors.ink,
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
              borderSide: const BorderSide(color: AppColors.line, width: 1.1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line, width: 1.1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(
                color: AppColors.brandBlueDeep,
                width: 1.6,
              ),
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
            counterText: '',
          ),
        ),
        if (counterLabel.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              counterLabel,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.1,
                color: AppColors.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
