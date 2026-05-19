import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _money = NumberFormat.decimalPattern('fr_FR');
  static final _date = DateFormat('dd/MM/yyyy', 'fr_FR');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
  static final _dateTimeDash = DateFormat('dd-MM-yyyy HH:mm', 'fr_FR');

  static String money(num value) => '${_money.format(value)} MRU';
  static String number(num value) => _money.format(value);
  static String numberFr(num value) => _money.format(value);
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);
  static String dateTimeDash(DateTime d) => _dateTimeDash.format(d);

  static String shortPublicCode(String code) {
    if (code.length <= 12) return code;
    return '${code.substring(0, 4)} ${code.substring(4, 8)} ${code.substring(8, 12)}';
  }
}
