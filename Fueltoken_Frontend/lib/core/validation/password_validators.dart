/// Mot de passe / code secret mobile : **exactement 4 chiffres**.
///
/// Ne pas confondre avec l'OTP SMS Chinguisoft, qui est un code de
/// verification a 6 chiffres.
const int kSecretCodeLength = 4;
const int kOtpSmsCodeLength = 6;

final RegExp kFourDigitNumericPasswordRegExp = RegExp(r'^\d{4}$');

String? validateFourDigitNumericPassword(String? raw) {
  if (raw == null || raw.isEmpty) {
    return 'Saisissez votre mot de passe';
  }
  if (!kFourDigitNumericPasswordRegExp.hasMatch(raw)) {
    return 'Le mot de passe doit être composé de 4 chiffres uniquement.';
  }
  return null;
}

/// Alias temporaire de compatibilite : les ecrans doivent utiliser
/// validateFourDigitNumericPassword.
@Deprecated('Use validateFourDigitNumericPassword instead.')
String? validateSixDigitNumericPassword(String? raw) {
  return validateFourDigitNumericPassword(raw);
}

/// Connexion et autres écrans : longueur minimale (lettres, chiffres, symboles).
String? validateAppPassword(String? raw, {int minLength = 4}) {
  if (raw == null || raw.isEmpty) {
    return 'Saisissez votre mot de passe';
  }
  if (raw.length < minLength) {
    return 'Au moins $minLength caractères (lettres, chiffres ou mélange).';
  }
  return null;
}
