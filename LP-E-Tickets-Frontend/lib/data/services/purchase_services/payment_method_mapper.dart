import '../../../domain/models/purchase/payment_method.dart';

/// Converts payment-method API records to the purchase domain model.
class PaymentMethodMapper {
  PaymentMethodMapper._();

  static PaymentMethod fromJson(Map<String, dynamic> json) {
    final code = _clean(json['code']);
    final name = _clean(json['display_name']) ?? _clean(json['name']);
    final merchantCode = _clean(json['merchant_code']);
    if (code == null || name == null || merchantCode == null) {
      throw const FormatException('Moyen de paiement incomplet.');
    }
    return PaymentMethod(
      id: _intOrNull(json['id']),
      code: code.toLowerCase(),
      name: name,
      merchantCode: merchantCode,
      instructions: _clean(json['instructions']),
      colorHex: _clean(json['color_hex']),
      logoData: _clean(json['logo_data']) ?? _clean(json['image_128']),
    );
  }

  static String? _clean(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'false' ? null : text;
  }

  static int? _intOrNull(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString().trim() ?? '');
  }
}
