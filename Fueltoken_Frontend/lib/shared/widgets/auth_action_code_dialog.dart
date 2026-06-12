import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      throw StateError('Session utilisateur introuvable.');
    }
    final storedPassword = await LoginSessionCache.lastPassword();
    if (storedPassword == null || storedPassword.isEmpty) {
      throw StateError(
        'Mot de passe de validation introuvable. Reconnectez-vous.',
      );
    }
    if (!context.mounted) {
      return false;
    }

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
              final validationError = validateSixDigitNumericPassword(password);
              if (validationError != null) {
                setState(() {
                  errorText = validationError;
                });
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
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.line.withValues(alpha: 0.9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 34,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.clientCtaGradient,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(27),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 13.5,
                                      height: 1.45,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: AppColors.primarySoft.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  14,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.pin_outlined,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Saisie sécurisée à 6 chiffres. Le clavier numérique reste actif pendant la vérification.',
                                        style: TextStyle(
                                          fontSize: 13.2,
                                          height: 1.45,
                                          color: AppColors.body,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                enabled: !busy,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                maxLength: 6,
                                obscureText: obscure,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2,
                                  color: AppColors.ink,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  hintText: '000000',
                                  counterText: '',
                                  errorText: errorText,
                                  filled: true,
                                  fillColor: AppColors.successSurface,
                                  labelStyle: const TextStyle(
                                    color: AppColors.leaderGreenDark,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.password_outlined,
                                    size: 21,
                                    color: AppColors.leaderGreenDark,
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed: busy
                                        ? null
                                        : () {
                                            setState(() => obscure = !obscure);
                                          },
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!busy) {
                                    submit();
                                  }
                                },
                              ),
                              if (errorText != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSurface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.danger.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.danger,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          errorText!,
                                          style: const TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 13.2,
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.of(
                                        dialogContext,
                                      ).pop(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  side: BorderSide(
                                    color: AppColors.line.withValues(
                                      alpha: 0.9,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Annuler',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: busy ? null : submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.leaderGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Valider',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
