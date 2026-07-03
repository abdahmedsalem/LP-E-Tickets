import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/validation/password_validators.dart';
import '../../../shared/widgets/app_message.dart';
import '../bloc/auth_bloc.dart';

class SessionPinLockScreen extends StatefulWidget {
  const SessionPinLockScreen({super.key});

  @override
  State<SessionPinLockScreen> createState() => _SessionPinLockScreenState();
}

class _SessionPinLockScreenState extends State<SessionPinLockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  bool _obscure = true;
  bool _openForgotPasswordAfterLogout = false;

  @override
  void dispose() {
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  void _submit(AuthState state) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bloc = context.read<AuthBloc>();
    final pin = _pin.text.trim();
    if (state.status == AuthStatus.pinSetupRequired) {
      bloc.add(AuthLocalPinSetupRequested(pin: pin));
      return;
    }
    bloc.add(AuthUnlockRequested(pin: pin));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage || a.status != b.status,
      listener: (ctx, state) {
        if (_openForgotPasswordAfterLogout &&
            state.status == AuthStatus.unauthenticated) {
          _openForgotPasswordAfterLogout = false;
          ctx.go('/forgot-password');
          return;
        }

        final msg = state.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          AppMessage.error(ctx, msg);
        }
      },
      builder: (ctx, state) {
        final setup = state.status == AuthStatus.pinSetupRequired;
        final busy = state.status == AuthStatus.authenticating;
        final userName = state.user?.name.trim();
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.white,
            body: SafeArea(
              child: GestureDetector(
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
                            const SizedBox(height: 24),
                            Center(
                              child: Image.asset(
                                'designs/lplogo.jfif',
                                height: 112,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Icon(
                              setup
                                  ? Icons.enhanced_encryption_outlined
                                  : Icons.lock_outline_rounded,
                              size: 42,
                              color: const Color(0xFF203A73),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              setup
                                  ? 'Définir votre PIN'
                                  : 'Déverrouiller l’application',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                color: Color(0xFF1E293B),
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              setup
                                  ? 'Votre connexion OTP est validée. Choisissez maintenant un PIN à 4 chiffres pour les prochaines ouvertures.'
                                  : 'Session restaurée${userName == null || userName.isEmpty ? '' : ' pour $userName'}. Saisissez votre PIN pour continuer.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _PinField(
                              controller: _pin,
                              obscure: _obscure,
                              hint: 'PIN à 4 chiffres',
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
                              validator: validateFourDigitNumericPassword,
                            ),
                            if (setup) ...[
                              const SizedBox(height: 14),
                              _PinField(
                                controller: _pinConfirm,
                                obscure: _obscure,
                                hint: 'Confirmer le PIN',
                                validator: (value) {
                                  final err = validateFourDigitNumericPassword(
                                    value,
                                  );
                                  if (err != null) return err;
                                  if (value != _pin.text) {
                                    return 'Les PIN ne correspondent pas.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 54,
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
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: busy ? null : () => _submit(state),
                                    child: Center(
                                      child: busy
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              setup
                                                  ? 'Enregistrer le PIN'
                                                  : 'Déverrouiller',
                                              style: const TextStyle(
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
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      if (!setup) {
                                        _openForgotPasswordAfterLogout = true;
                                      }
                                      context.read<AuthBloc>().add(
                                        const AuthLogoutRequested(),
                                      );
                                    },
                              child: Text(
                                setup
                                    ? 'Annuler et revenir à la connexion'
                                    : 'PIN oublié ?',
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
      },
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.validator,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final String? Function(String?) validator;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: kSecretCodeLength,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: 8,
        color: Color(0xFF1E293B),
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        suffixIcon: trailing,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFC7CEDA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF203A73), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
        ),
      ),
      validator: validator,
    );
  }
}
