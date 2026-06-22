import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../core/validation/contact_validators.dart';
import '../../../shared/widgets/app_message.dart';
import 'forgot_otp_flow_screens.dart';

/// Recuperation : envoi OTP -> saisie code -> nouveau PIN.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneLocal = TextEditingController();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phoneLocal.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _phoneLocal.removeListener(_onFieldChanged);
    _phoneLocal.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  String get _phoneFull =>
      _phoneLocal.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final response = await OdooAuthService.instance.requestPasswordResetOtp(
        phoneFull: _phoneFull,
      );
      final data = response['data'];
      final challengeId = data is Map
          ? int.tryParse(data['otp_challenge_id']?.toString() ?? '')
          : null;
      if (!mounted) return;
      AppMessage.info(context, 'Code envoye.');
      context.push(
        '/forgot-password/verify-otp',
        extra: ForgotOtpRouteArgs(
          identifier: _phoneFull,
          challengeId: challengeId,
        ),
      );
    } on StateError catch (e) {
      if (mounted) {
        AppMessage.error(context, e.message);
      }
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
        backgroundColor: AppColors.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
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
                        Center(
                          child: Image.asset(
                            'designs/lplogo.jfif',
                            height: 128,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Recuperation du PIN',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Entrez votre numero pour recevoir le code de verification.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: AppColors.line),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0F0B1220),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _AuthTextField(
                                  controller: _phoneLocal,
                                  label: 'Numero',
                                  hint: 'XXXXXXXX',
                                  keyboardType: TextInputType.number,
                                  maxLength: 8,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: validateMrLocalPhone,
                                  counterLabel:
                                      '${_phoneLocal.text.trim().replaceAll(RegExp(r'\D'), '').length}/8',
                                ),
                                const SizedBox(height: 20),
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
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.4,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Text(
                                                  'Envoyer le code',
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
                                const SizedBox(height: 14),
                                const Text(
                                  'Le code est envoye par SMS sur votre numero de telephone.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF64748B),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.maxLength,
    this.validator,
    this.inputFormatters,
    this.counterLabel,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final int? maxLength;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final String? counterLabel;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: counterLabel ?? '',
      ),
      validator: validator,
    );
  }
}
