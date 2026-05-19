import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/services/otp_remote_service.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/fuel_mark.dart';
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
  bool _obscure = true;
  final _otpService = OtpRemoteService();
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

  /// Après validation du formulaire : choix du canal, puis envoi du code de vérification.
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
                ? 'Définissez API_BASE_URL (URL de votre service REST OTP/inscription, '
                    'ex. https://api.example.com).'
                : 'Le service d’envoi du code est indisponible. Réessayez plus '
                    'tard ou contactez le support.',
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
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(
              title: "S'inscrire",
              subtitle: 'Créer un compte FuelToken',
              onBack: () => context.go('/login'),
            ),
            Expanded(
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
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(child: FuelMark(size: 42)),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.waving_hand_outlined,
                                    size: 26,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Bienvenue',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Quelques informations et c’est parti',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.primarySoft),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.shield_outlined,
                                        color: AppColors.primaryDark, size: 16),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Simple, sécurisé, prêt à rouler.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryDark,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              _LabeledField(
                                label: 'NOM COMPLET',
                                child: TextFormField(
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: _decoration(
                                    icon: Icons.person_outline,
                                    hint: 'ex. Mohamed Ould A.',
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Nom requis'
                                          : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LabeledField(
                                label: 'TÉLÉPHONE',
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 48,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(12),
                                        border:
                                            Border.all(color: AppColors.line),
                                      ),
                                      child: const Text(
                                        kMauritaniaPhonePrefix,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phoneLocal,
                                        keyboardType: TextInputType.number,
                                        maxLength: 8,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: _decoration(
                                          icon: Icons.phone_android_outlined,
                                          hint: 'XXXXXXXX',
                                        ).copyWith(counterText: ''),
                                        validator: (v) =>
                                            validateMrLocalPhone(v),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LabeledField(
                                label: 'EMAIL',
                                child: TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  decoration: _decoration(
                                    icon: Icons.mail_outline,
                                    hint: 'nom@exemple.com',
                                  ),
                                  validator: validateAppEmail,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LabeledField(
                                label: 'MOT DE PASSE',
                                child: TextFormField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _decoration(
                                    icon: Icons.lock_outline,
                                    hint: '6 chiffres',
                                    suffix: IconButton(
                                      iconSize: 18,
                                      splashRadius: 18,
                                      color: AppColors.muted,
                                      icon: Icon(_obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                  ).copyWith(counterText: ''),
                                  validator: validateSixDigitNumericPassword,
                                ),
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                height: 50,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      loading ? null : _onCreateAccount,
                                  child: loading
                                      ? const AppInlineLoading(size: 22)
                                      : const Text('Créer mon compte'),
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
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required IconData icon,
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 6),
        child: Icon(icon, size: 18, color: AppColors.muted),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 32, minHeight: 32),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
