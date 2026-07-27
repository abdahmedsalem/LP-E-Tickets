import 'package:intl/intl.dart';

class Formatters {
  static const fallbackCurrency = 'MRU';
  static String defaultCurrency = fallbackCurrency;
  Formatters._();

  static final _money = NumberFormat.decimalPattern('fr_FR');
  static final _date = DateFormat('dd-MM-yyyy');
  static final _dateTime = DateFormat('dd-MM-yyyy HH:mm:ss');
  static final _dateTimeDash = DateFormat('dd-MM-yyyy HH:mm:ss');

  static DateTime _local(DateTime d) => d.isUtc ? d.toLocal() : d;

  static void setDefaultCurrency(String? currency) {
    final unit = currency?.trim();
    if (unit != null && unit.isNotEmpty) {
      defaultCurrency = unit;
    }
  }

  static String currencyOrDefault([String? currency]) {
    final unit = currency?.trim();
    return unit != null && unit.isNotEmpty ? unit : defaultCurrency;
  }

  static String money(num value, {String? currency}) {
    final unit = currencyOrDefault(currency);
    return '${_money.format(value)} $unit';
  }

  static String number(num value) => _money.format(value);
  static String numberFr(num value) => _money.format(value);

  static String date(DateTime d) => _date.format(_local(d));
  static String dateTime(DateTime d) => _dateTime.format(_local(d));
  static String dateTimeDash(DateTime d) => _dateTimeDash.format(_local(d));

  static String carnetTypeLabelFromServer(
    String serverLabel, {
    String? fallbackCode,
  }) {
    final label = serverLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (label.isNotEmpty) return label;

    final code = fallbackCode?.trim();
    if (code != null && code.isNotEmpty && code != '—') return code;
    return '';
  }

  static String shortPublicCode(String code) {
    if (code.length <= 12) return code;
    return '${code.substring(0, 4)} ${code.substring(4, 8)} ${code.substring(8, 12)}';
  }
}
