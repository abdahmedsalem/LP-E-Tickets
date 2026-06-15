import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/login_session_cache.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/password_validators.dart';
import '../../features/auth/bloc/auth_bloc.dart';

/// Demande le mot de passe du compte actuellement connecté avant une action sensible.
Future<bool> showSensitiveActionPasswordDialog(
  BuildContext context, {
  required String title,
  required String description,
}) async {
  final controller = TextEditingController();
  try {
    final state = context.read<AuthBloc>().state;
    final user = state.user;
    if (user == null) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Session introuvable'),
            content: Text('Reconnectez-vous pour continuer.'),
          ),
        );
      }
      return false;
    }

    final storedPassword = await LoginSessionCache.lastPassword();
    if (storedPassword == null || storedPassword.isEmpty) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Mot de passe introuvable'),
            content: Text('Reconnectez-vous pour continuer.'),
          ),
        );
      }
      return false;
    }
    if (!context.mounted) return false;

    bool busy = false;
    bool obscure = true;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> submit() async {
              final password = controller.text.trim();
              final validationError = validateFourDigitNumericPassword(password);
              if (validationError != null) {
                setState(() => errorText = validationError);
                return;
              }
              setState(() {
                busy = true;
                errorText = null;
              });
              try {
                if (password != storedPassword) {
                  throw StateError('Mot de passe incorrect.');
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setState(() {
                  errorText = e.toString().replaceFirst('Exception: ', '');
                  busy = false;
                });
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFFE8EAED)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: AppColors.leaderGreen,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                color: AppColors.leaderGreen,
                                size: 42,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _PinCodeBoxes(
                              controller: controller,
                              enabled: !busy,
                              obscure: obscure,
                              errorText: errorText,
                              onChanged: () {
                                if (busy) return;
                                final current = controller.text.trim();
                                setState(() {
                                  if (errorText != null) errorText = null;
                                });
                                if (current.length == kSecretCodeLength) {
                                  submit();
                                }
                              },
                              onSubmitted: () {
                                if (!busy) submit();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.of(dialogContext).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.ink,
                          disabledBackgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFE8EAED)),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  } finally {
    controller.dispose();
  }
}

/// Alias conservé pour compatibilité avec l'ancien nom.
Future<bool> showSensitiveActionAuthCodeDialog(
  BuildContext context, {
  required String title,
  required String description,
}) {
  return showSensitiveActionPasswordDialog(
    context,
    title: title,
    description: description,
  );
}

class _PinCodeBoxes extends StatelessWidget {
  const _PinCodeBoxes({
    required this.controller,
    required this.enabled,
    required this.obscure,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool obscure;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final value = controller.text.trim();
    final dots = List.generate(kSecretCodeLength, (i) => i < value.length ? value[i] : '');

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.01,
              child: TextField(
                controller: controller,
                autofocus: true,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: kSecretCodeLength,
                obscureText: obscure,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmitted(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(kSecretCodeLength, (index) {
                final filled = dots[index].isNotEmpty;
                final active = value.length == index;
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: index == kSecretCodeLength - 1 ? 0 : 8,
                  ),
                  child: Container(
                    width: 42,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: active
                            ? Colors.black
                            : const Color(0xFFB8BDC6),
                        width: active ? 2 : 1.6,
                      ),
                    ),
                    child: Text(
                      filled ? (obscure ? '•' : dots[index]) : '',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        height: 1,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
