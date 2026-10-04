import 'package:intl/intl.dart';

class Formatters {
  static const fallbackCurrency = 'MRU';
  static String defaultCurrency = fallbackCurrency;
  Formatters._();

  static String _locale = 'fr_FR';
  static final Map<String, NumberFormat> _moneyFormats = {};
  static final Map<String, DateFormat> _dateFormats = {};
  static final Map<String, DateFormat> _dateTimeFormats = {};
  static final Map<String, DateFormat> _dateTimeShortFormats = {};
  static final Map<String, DateFormat> _timeFormats = {};

  static void setLocaleCode(String code) {
    _locale = code == 'ar' ? 'ar' : 'fr_FR';
  }

  static NumberFormat get _money => _moneyFormats.putIfAbsent(
    _locale,
    () => NumberFormat.decimalPattern(_locale),
  );

  static DateFormat get _date => _dateFormats.putIfAbsent(
    _locale,
    () => DateFormat('dd-MM-yyyy', _locale),
  );

  static DateFormat get _dateTime => _dateTimeFormats.putIfAbsent(
    _locale,
    () => DateFormat('dd-MM-yyyy HH:mm:ss', _locale),
  );

  static DateFormat get _dateTimeDash => _dateTime;

  static DateFormat get _dateTimeShort => _dateTimeShortFormats.putIfAbsent(
    _locale,
    () => DateFormat('dd-MM-yyyy HH:mm', _locale),
  );

  static DateFormat get _time =>
      _timeFormats.putIfAbsent(_locale, () => DateFormat('HH:mm:ss', _locale));

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
  static String dateTimeShort(DateTime d) => _dateTimeShort.format(_local(d));
  static String time(DateTime d) => _time.format(_local(d));

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
