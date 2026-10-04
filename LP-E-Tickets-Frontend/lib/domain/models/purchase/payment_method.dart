/// Payment option exposed to purchase flows after API mapping.
class PaymentMethod {
  const PaymentMethod({
    this.id,
    required this.code,
    required this.name,
    required this.merchantCode,
    this.instructions,
    this.colorHex,
    this.logoData,
  });

  final int? id;
  final String code;
  final String name;
  final String merchantCode;
  final String? instructions;
  final String? colorHex;
  final String? logoData;

  String get _compactDestination =>
      merchantCode.trim().replaceAll(RegExp(r'[\s-]'), '');

  bool get destinationIsPhoneNumber =>
      RegExp(r'^\d{8}$').hasMatch(_compactDestination);

  bool get destinationIsMerchantCode =>
      RegExp(r'^(?:\d{4}|\d{6})$').hasMatch(_compactDestination);

  String get destinationLabel {
    if (destinationIsPhoneNumber) return 'Numéro de téléphone';
    if (destinationIsMerchantCode) return 'Code commerçant';
    return 'Code commerçant / Numéro de téléphone';
  }

  String get destinationCopiedLabel {
    if (destinationIsPhoneNumber) return 'Numéro';
    if (destinationIsMerchantCode) return 'Code commerçant';
    return 'Identifiant de paiement';
  }

  String get initial {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return '?';
    return String.fromCharCode(cleanName.runes.first).toUpperCase();
  }
}
