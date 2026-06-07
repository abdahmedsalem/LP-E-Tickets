import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _money = NumberFormat.decimalPattern('fr_FR');
  static final _date = DateFormat('dd/MM/yyyy', 'fr_FR');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
  static final _dateTimeDash = DateFormat('dd-MM-yyyy HH:mm', 'fr_FR');

  static DateTime _local(DateTime d) => d.isUtc ? d.toLocal() : d;

  static String money(num value) => '${_money.format(value)} MRU';
  static String number(num value) => _money.format(value);
  static String numberFr(num value) => _money.format(value);
  static String carnetTypeLabel(int size, int faceValue) =>
      'Carnet ${numberFr(size)} × ${numberFr(faceValue)}';
  static String date(DateTime d) => _date.format(_local(d));
  static String dateTime(DateTime d) => _dateTime.format(_local(d));
  static String dateTimeDash(DateTime d) => _dateTimeDash.format(_local(d));

  static String normalizeCarnetTypeLabel(
    String raw, {
    int? fallbackSize,
    int? fallbackFaceValue,
  }) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isNotEmpty) {
      final match = RegExp(
        r'^carnet\s+([\d\s]+)\s*(?:x|×|Ã—|\*)\s*([\d\s]+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) {
        final size = int.tryParse(
          match.group(1)!.replaceAll(RegExp(r'\D'), ''),
        );
        final faceValue = int.tryParse(
          match.group(2)!.replaceAll(RegExp(r'\D'), ''),
        );
        if (size != null && size > 0 && faceValue != null && faceValue > 0) {
          return carnetTypeLabel(size, faceValue);
        }
      }
      return text;
    }
    if ((fallbackSize ?? 0) > 0 && (fallbackFaceValue ?? 0) > 0) {
      return carnetTypeLabel(fallbackSize!, fallbackFaceValue!);
    }
    return text;
  }

  static String shortPublicCode(String code) {
    if (code.length <= 12) return code;
    return '${code.substring(0, 4)} ${code.substring(4, 8)} ${code.substring(8, 12)}';
  }
}
