import '../../../domain/models/purchase/payment_method.dart';

/// Converts payment-method API records to the purchase domain model.
class PaymentMethodMapper {
  PaymentMethodMapper._();

  static PaymentMethod fromJson(Map<String, dynamic> json) {
    final code = _nonEmptyText(json['code']);
    final name =
        _nonEmptyText(json['display_name']) ?? _nonEmptyText(json['name']);
    final merchantCode = _nonEmptyText(json['merchant_code']);
    if (code == null || name == null || merchantCode == null) {
      throw const FormatException('Moyen de paiement incomplet.');
    }
    return PaymentMethod(
      id: _integerOrNull(json['id']),
      code: code.toLowerCase(),
      name: name,
      merchantCode: merchantCode,
      instructions: _nonEmptyText(json['instructions']),
      colorHex: _nonEmptyText(json['color_hex']),
      logoData:
          _nonEmptyText(json['logo_data']) ?? _nonEmptyText(json['image_128']),
    );
  }

  static String? _nonEmptyText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'false' ? null : text;
  }

  static int? _integerOrNull(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString().trim() ?? '');
  }
}
