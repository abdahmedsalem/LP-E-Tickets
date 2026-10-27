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

  String get destinationLabel => 'Code commerçant';

  String get destinationCopiedLabel => 'Code commerçant';

  String get initial {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return '?';
    return String.fromCharCode(cleanName.runes.first).toUpperCase();
  }
}
