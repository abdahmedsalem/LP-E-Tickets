import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/odoo_auth_rpc_config.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../bloc/auth_bloc.dart';
import 'register_verify_otp_screen.dart';
import '../../../shared/widgets/app_message.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phoneLocal = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _sendingOtp = false;

  @override
  void initState() {
    super.initState();
    _phoneLocal.addListener(_onFieldChanged);
    _password.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _phoneLocal.removeListener(_onFieldChanged);
    _password.removeListener(_onFieldChanged);
    _name.dispose();
    _phoneLocal.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  String get _phoneFull =>
      fullMrPhoneFromLocal8(_phoneLocal.text.replaceAll(RegExp(r'\D'), ''));

  Future<void> _onCreateAccount() async {
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
        phoneFull: _phoneFull,
      );
      final data = response['data'];
      final challengeId = data is Map
          ? int.tryParse(data['otp_challenge_id']?.toString() ?? '')
          : null;
      if (!mounted) return;
      AppMessage.info(context, 'Code OTP envoyé par SMS.');
      if (challengeId == null) {
        throw Exception('Challenge OTP introuvable dans la réponse serveur.');
      }
      context.push(
        '/register/verify-otp',
        extra: RegisterOtpRouteArgs(
          name: _name.text.trim(),
          phoneFull: _phoneFull,
          password: _password.text,
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

  @override
  Widget build(BuildContext context) {
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
          },
          builder: (ctx, state) {
            final loading = _sendingOtp;
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
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
                          Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => context.go('/login'),
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
                          const _RegisterWelcomeCopy(),
                          const SizedBox(height: 34),
                          const _RegisterSectionTitle(title: 'Inscription'),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _name,
                            hint: 'Nom complet',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Nom requis'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          _RegisterField(
                            controller: _phoneLocal,
                            hint: 'Téléphone',
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateMrLocalPhone,
                            counterLabel:
                                '${_phoneLocal.text.trim().replaceAll(RegExp(r'\D'), '').length}/8',
                          ),
                          const SizedBox(height: 14),
                          _RegisterField(
                            controller: _password,
                            hint: 'Mot de passe',
                            obscure: _obscure,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateSixDigitNumericPassword,
                            counterLabel: '${_password.text.trim().length}/6',
                            trailing: IconButton(
                              splashRadius: 20,
                              iconSize: 20,
                              color: const Color(0xFF7A8798),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
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
                                  onTap: loading ? null : _onCreateAccount,
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
                                        : const Text(
                                            'Créer mon compte',
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
                                  'Déjà un compte ?',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => ctx.go('/login'),
                                  child: const Text(
                                    'Se connecter',
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

class _RegisterWelcomeCopy extends StatelessWidget {
  const _RegisterWelcomeCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Créez votre',
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

class _RegisterSectionTitle extends StatelessWidget {
  const _RegisterSectionTitle({required this.title});

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

class _RegisterNoticeCard extends StatelessWidget {
  const _RegisterNoticeCard({required this.message});

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
              Icons.info_outline_rounded,
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
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
