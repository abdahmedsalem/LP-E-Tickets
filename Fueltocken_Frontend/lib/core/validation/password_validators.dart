/// Mot de passe inscription / réinitialisation : **exactement 6 chiffres**.
final RegExp kSixDigitNumericPasswordRegExp = RegExp(r'^\d{6}$');

String? validateSixDigitNumericPassword(String? raw) {
  if (raw == null || raw.isEmpty) {
    return 'Saisissez votre mot de passe';
  }
  if (!kSixDigitNumericPasswordRegExp.hasMatch(raw)) {
    return 'Le mot de passe doit être composé de 6 chiffres uniquement.';
  }
  return null;
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
