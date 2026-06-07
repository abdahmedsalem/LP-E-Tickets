import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../data/services/otp_remote_service.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import 'forgot_otp_flow_screens.dart';
import '../../../shared/widgets/app_message.dart';

/// Récupération : envoi OTP → saisie code → nouveau mot de passe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phoneLocal = TextEditingController();
  bool _usePhone = true;
  bool _busy = false;
  final _otp = OtpRemoteService();

  @override
  void dispose() {
    _email.dispose();
    _phoneLocal.dispose();
    super.dispose();
  }

  String get _phoneFull =>
      fullMrPhoneFromLocal8(_phoneLocal.text.replaceAll(RegExp(r'\D'), ''));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final channel = _usePhone ? OtpChannel.sms : OtpChannel.email;
      final identifier = _usePhone ? _phoneFull : _email.text.trim();
      await _otp.sendForgotOtp(channel: channel, identifier: identifier);
      if (!mounted) return;
      AppMessage.info(context, 'Code envoyé.');
      context.push(
        '/forgot-password/verify-otp',
        extra: ForgotOtpRouteArgs(
          identifier: identifier,
          channel: channel,
        ),
      );
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => context.pop(),
              ),
              title: const Text(
                'Mot de passe oublié',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: AppColors.loginHeroGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppColors.softShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lock_reset_rounded,
                                  color: Colors.white.withValues(alpha: 0.95),
                                  size: 28),
                              const SizedBox(height: 12),
                              Text(
                                'Réinitialisation sécurisée',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withValues(alpha: 0.98),
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Nous envoyons un code à 6 chiffres, puis vous choisissez un nouveau mot de passe.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: AppColors.line.withValues(alpha: 0.85),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.leaderGreen.withValues(alpha: 0.07),
                                blurRadius: 32,
                                offset: const Offset(0, 14),
                                spreadRadius: -8,
                              ),
                              const BoxShadow(
                                color: Color(0x120B1220),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ChannelToggle(
                                    usePhone: _usePhone,
                                    onChanged: (v) {
                                      setState(() {
                                        _usePhone = v;
                                        _email.clear();
                                        _phoneLocal.clear();
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  if (_usePhone)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          height: 52,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: AppColors.background,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: AppColors.line),
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
                                            decoration: InputDecoration(
                                              labelText: 'Numéro',
                                              hintText: 'XXXXXXXX',
                                              counterText: '',
                                            ),
                                            validator: (v) =>
                                                validateMrLocalPhone(v),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    TextFormField(
                                      controller: _email,
                                      keyboardType:
                                          TextInputType.emailAddress,
                                      autocorrect: false,
                                      decoration: const InputDecoration(
                                        labelText: 'Adresse email',
                                        hintText: 'vous@exemple.com',
                                      ),
                                      validator: validateAppEmail,
                                    ),
                                  const SizedBox(height: 22),
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _busy ? null : _submit,
                                      child: _busy
                                          ? const AppInlineLoading(size: 22)
                                          : const Text('Envoyer le code'),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextButton(
                                    onPressed: () => context.go('/login'),
                                    child: const Text(
                                      'Retour à la connexion',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelToggle extends StatelessWidget {
  const _ChannelToggle({required this.usePhone, required this.onChanged});

  final bool usePhone;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(bool selected, IconData icon, String label, bool phone) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(phone),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : AppColors.lineSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? AppColors.primary : AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? AppColors.primaryDark : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(usePhone, Icons.sms_outlined, 'SMS / téléphone', true),
        const SizedBox(width: 10),
        chip(!usePhone, Icons.alternate_email_rounded, 'Email', false),
      ],
    );
  }
}
