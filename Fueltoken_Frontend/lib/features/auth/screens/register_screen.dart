import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_api_config.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/services/otp_remote_service.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/otp_channel_picker_sheet.dart';
import 'register_verify_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phoneLocal = TextEditingController();
  final _password = TextEditingController();
  final _otpService = OtpRemoteService();
  bool _obscure = true;
  bool _sendingOtp = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phoneLocal.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _phoneFull =>
      fullMrPhoneFromLocal8(_phoneLocal.text.replaceAll(RegExp(r'\D'), ''));

  Future<void> _onCreateAccount() async {
    if (!_formKey.currentState!.validate()) return;
    final channel = await showOtpChannelPickerSheet(context);
    if (channel == null || !mounted) return;
    if (!AppApiConfig.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kDebugMode
                ? 'Définissez API_BASE_URL (URL de votre service REST OTP/inscription, ex. https://api.example.com).'
                : 'Le service d’envoi du code est indisponible. Réessayez plus tard ou contactez le support.',
          ),
        ),
      );
      return;
    }
    await _sendRegistrationOtp(channel);
  }

  Future<void> _sendRegistrationOtp(OtpChannel channel) async {
    setState(() => _sendingOtp = true);
    try {
      await _otpService.sendRegistrationOtp(
        channel: channel,
        email: _email.text.trim(),
        name: _name.text.trim(),
        phoneFull: _phoneFull,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            channel == OtpChannel.email
                ? 'Code envoyé par e-mail.'
                : 'Code envoyé par SMS.',
          ),
        ),
      );
      context.push(
        '/register/verify-otp',
        extra: RegisterOtpRouteArgs(
          email: _email.text.trim(),
          name: _name.text.trim(),
          phoneFull: _phoneFull,
          password: _password.text,
          channel: channel,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(state.errorMessage!)),
              );
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
                          const SizedBox(height: 10),
                          const _RegisterBrandBlock(),
                          const SizedBox(height: 44),
                          const _RegisterWelcomeCopy(),
                          const SizedBox(height: 34),
                          const _RegisterSectionTitle(title: 'Inscription'),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _name,
                            hint: 'Nom complet',
                            icon: Icons.person_outline_rounded,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Nom requis'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                          _RegisterField(
                            controller: _phoneLocal,
                            hint: 'Téléphone',
                            icon: Icons.phone_android_outlined,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateMrLocalPhone,
                            prefixText: '$kMauritaniaPhonePrefix ',
                          ),
                          const SizedBox(height: 14),
                          _RegisterField(
                            controller: _email,
                            hint: 'Adresse email',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            validator: validateAppEmail,
                          ),
                          const SizedBox(height: 14),
                          _RegisterField(
                            controller: _password,
                            hint: 'Mot de passe',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscure,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: validateSixDigitNumericPassword,
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
                          const SizedBox(height: 18),
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
                            _RegisterNoticeCard(
                              message: state.errorMessage!,
                            ),
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

class _RegisterBrandBlock extends StatelessWidget {
  const _RegisterBrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_fueltoken.png',
              width: 86,
              height: 86,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                _RegisterWordmark(),
                SizedBox(height: 0),
                Text(
                  'SMART FUEL WALLET',
                  style: TextStyle(
                    fontSize: 10.0,
                    letterSpacing: 4.6,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _RegisterWordmark extends StatelessWidget {
  const _RegisterWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Fuel',
            style: TextStyle(
              color: Color(0xFF203A73),
              fontSize: 34,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          TextSpan(
            text: 'Token',
            style: TextStyle(
              color: Color(0xFF2EA043),
              fontSize: 34,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
        ],
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
    required this.icon,
    required this.validator,
    this.obscure = false,
    this.keyboardType,
    this.autocorrect = true,
    this.maxLength,
    this.inputFormatters,
    this.trailing,
    this.prefixText,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? trailing;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
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
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Icon(icon, size: 20, color: const Color(0xFF7A8798)),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w700,
        ),
        suffixIcon: trailing,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFC7CEDA), width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFC7CEDA), width: 1.1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Color(0xFF203A73), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
        ),
        counterText: '',
      ),
    );
  }
}
