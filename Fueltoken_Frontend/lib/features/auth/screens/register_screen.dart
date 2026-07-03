import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/pending_signup_store.dart';
import '../../../core/config/odoo_auth_rpc_config.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/fuel_mark.dart';
import '../bloc/auth_bloc.dart';
import 'register_verify_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phoneLocal = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _sendingOtp = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onFieldChanged);
    _phoneLocal.addListener(_onFieldChanged);
    _pin.addListener(_onFieldChanged);
    _pinConfirm.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onFieldChanged);
    _phoneLocal.removeListener(_onFieldChanged);
    _pin.removeListener(_onFieldChanged);
    _pinConfirm.removeListener(_onFieldChanged);
    _name.dispose();
    _phoneLocal.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  String get _phoneLocalDigits =>
      _phoneLocal.text.replaceAll(RegExp(r'\D'), '');

  bool get _formLooksValid {
    final nameOk = _name.text.trim().isNotEmpty;
    final phoneOk = validateMrLocalPhone(_phoneLocal.text) == null;
    final pin = _pin.text.trim();
    final pinOk = validateFourDigitNumericPassword(pin) == null;
    final pinConfirmOk = _pinConfirm.text.trim() == pin;
    return nameOk && phoneOk && pinOk && pinConfirmOk;
  }

  String? _validatePinConfirm(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Confirmez votre PIN';
    if (value != _pin.text.trim()) return 'Les PIN ne correspondent pas.';
    return null;
  }

  Future<void> _onCreateAccount() async {
    if (_sendingOtp || !_formLooksValid) return;
    if (!_formKey.currentState!.validate()) return;
    if (OdooAuthRpcConfig.requestOtpRoute.isEmpty ||
        OdooAuthRpcConfig.verifyOtpRoute.isEmpty) {
      if (!mounted) return;
      AppMessage.error(
        context,
        "L'inscription Odoo ACPEC n'est pas configurée sur cet appareil.",
      );
      return;
    }
    await _sendRegistrationOtp();
  }

  Future<void> _sendRegistrationOtp() async {
    setState(() => _sendingOtp = true);
    try {
      final response = await OdooAuthService.instance.requestSignupOtp(
        phoneFull: _phoneLocalDigits,
      );
      final challengeId = _extractChallengeId(response);
      if (!mounted) return;
      if (challengeId == null || challengeId <= 0) {
        AppMessage.error(
          context,
          'Le serveur n’a pas confirmé le code SMS. Réessayez.',
        );
        return;
      }
      final companyId = OdooAuthRpcConfig.signupDefaultCompanyId;
      await PendingSignupStore.save(
        name: _name.text.trim(),
        phoneFull: _phoneLocalDigits,
        challengeId: challengeId,
        companyId: companyId,
      );
      if (!mounted) return;
      AppMessage.info(context, 'Code SMS envoyé.');
      context.push(
        '/register/verify-otp',
        extra: RegisterOtpRouteArgs(
          name: _name.text.trim(),
          phoneFull: _phoneLocalDigits,
          pin: _pin.text,
          companyId: companyId,
          challengeId: challengeId,
        ),
      );
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  int? _extractChallengeId(Map<String, dynamic> response) {
    int? parseId(dynamic value) {
      if (value == null || value == false) return null;
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;
      return int.tryParse(raw);
    }

    final data = response['data'];
    if (data is Map) {
      final dataMap = Map<String, dynamic>.from(data);
      final fromData =
          parseId(dataMap['otp_challenge_id']) ??
          parseId(dataMap['challenge_id']);
      if (fromData != null && fromData > 0) return fromData;
    }

    final fromTop =
        parseId(response['otp_challenge_id']) ??
        parseId(response['challenge_id']);
    if (fromTop != null && fromTop > 0) return fromTop;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.failure &&
                state.errorMessage != null) {
              AppMessage.error(ctx, state.errorMessage!);
            }
          },
          builder: (ctx, state) {
            final loading = _sendingOtp;
            final canSubmit = _formLooksValid && !loading;
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _RegisterCompactHeader(),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _name,
                            hint: 'Nom complet',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Nom requis'
                                : null,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          _RegisterField(
                            controller: _phoneLocal,
                            hint: 'Numéro de téléphone',
                            keyboardType: TextInputType.phone,
                            maxLength: 8,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateMrLocalPhone,
                            counterLabel: '${_phoneLocalDigits.length}/8',
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          _RegisterField(
                            controller: _pin,
                            hint: 'Définir le PIN',
                            obscure: _obscure,
                            keyboardType: TextInputType.number,
                            maxLength: kSecretCodeLength,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateFourDigitNumericPassword,
                            counterLabel:
                                '${_pin.text.trim().length}/$kSecretCodeLength',
                            trailing: IconButton(
                              splashRadius: 20,
                              iconSize: 20,
                              color: AppColors.muted,
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          _RegisterField(
                            controller: _pinConfirm,
                            hint: 'Confirmer le PIN',
                            obscure: _obscureConfirm,
                            keyboardType: TextInputType.number,
                            maxLength: kSecretCodeLength,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validatePinConfirm,
                            counterLabel:
                                '${_pinConfirm.text.trim().length}/$kSecretCodeLength',
                            trailing: IconButton(
                              splashRadius: 20,
                              iconSize: 20,
                              color: AppColors.muted,
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (canSubmit) _onCreateAccount();
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: canSubmit ? _onCreateAccount : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.leaderGreen,
                                disabledBackgroundColor: const Color(
                                  0xFFCBD5E1,
                                ),
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Créer mon compte',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                const Text(
                                  'Vous avez déjà un compte ?',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await AppPreferences.setHasSeenOnboarding(
                                      true,
                                    );
                                    if (!ctx.mounted) return;
                                    ctx.go('/login');
                                  },
                                  child: const Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (state.status == AuthStatus.failure &&
                              state.errorMessage != null) ...[
                            const SizedBox(height: 18),
                            _RegisterNoticeCard(message: state.errorMessage!),
                          ],
                        ],
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

class _RegisterCompactHeader extends StatelessWidget {
  const _RegisterCompactHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => context.go('/login'),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: AppColors.brandBlueDeep,
                ),
              ),
            ),
            const Spacer(),
            const FuelLogo(size: 52, showOrgWordmark: false),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Créer un compte',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Leader Petroleum — Tickets Carburant',
          style: TextStyle(
            color: AppColors.brandBlueDeep,
            fontSize: 13.5,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Recevez un code SMS pour vérifier votre compte.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RegisterWelcomeCopy extends StatelessWidget {
  const _RegisterWelcomeCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Bienvenue sur Tickets Carburant',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            height: 1.12,
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.9,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Créez votre compte sécurisé avec votre téléphone et votre PIN.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.38,
            color: AppColors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RegisterSectionTitle extends StatelessWidget {
  const _RegisterSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        color: AppColors.brandBlueDeep,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _RegisterNoticeCard extends StatelessWidget {
  const _RegisterNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 22,
              color: AppColors.brandBlueDeep,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
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
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
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
    );
  }
}
