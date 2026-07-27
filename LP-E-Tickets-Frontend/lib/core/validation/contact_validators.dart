/// Préfixe national Mauritanie affiché à côté du champ (saisie = 8 chiffres locaux).
const String kMauritaniaPhonePrefix = '+222';

/// Exactement 8 chiffres, premier chiffre 2, 3 ou 4 uniquement.
final RegExp kMrLocalPhoneDigits = RegExp(r'^[234]\d{7}$');

/// Email « réel » : format courant suffisant pour l’app (pas une validation DNS).
final RegExp kAppEmailRegex = RegExp(
  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);

String? validateMrLocalPhone(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Numéro requis';
  }
  final d = raw.trim().replaceAll(RegExp(r'\D'), '');
  if (d.length != 8) {
    return '8 chiffres requis (commençant par 2, 3 ou 4)';
  }
  if (!kMrLocalPhoneDigits.hasMatch(d)) {
    return 'Doit commencer par 2, 3 ou 4 puis 7 autres chiffres';
  }
  return null;
}

String? validateAppEmail(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Email requis';
  }
  final e = raw.trim();
  if (!kAppEmailRegex.hasMatch(e)) {
    return 'Adresse email invalide';
  }
  return null;
}

/// Construit l’identifiant international +222XXXXXXXX
String fullMrPhoneFromLocal8(String local8Digits) {
  final d = local8Digits.replaceAll(RegExp(r'\D'), '');
  return '$kMauritaniaPhonePrefix$d';
}

String localMrDigitsFromFull(String phoneFull) {
  var d = phoneFull.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('222')) {
    d = d.substring(3);
  }
  return d;
}

/// Pour login mobile FuelToken : retourne toujours 8 chiffres locaux.
/// Tolère une saisie accidentelle avec +222/222, mais ne la propage jamais.
String normalizePhoneIdentifierForLookup(String raw) {
  final t = raw.trim();
  if (t.contains('@')) return t.toLowerCase();

  var d = t.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('222')) {
    d = d.substring(3);
  }
  if (kMrLocalPhoneDigits.hasMatch(d)) {
    return d;
  }
  return t.replaceAll(' ', '');
}
