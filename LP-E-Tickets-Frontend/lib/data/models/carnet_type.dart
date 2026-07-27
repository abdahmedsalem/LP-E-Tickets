import 'package:equatable/equatable.dart';

/// acpec.fuel.carnet.type — `validityDays` définit la durée de validité des faces
/// à partir de la **date de validation** du lot par l’admin.
class CarnetType extends Equatable {
  final String id;
  final String code; // e.g. C10-500
  final String name; // e.g. Ticket 10 × 500
  final int size; // faces per ticket
  final int faceValue;
  final String companyId;
  final bool active;
  final int validityDays;
  final int? apiTotalAmount;
  final String currencyName;
  final String currencySymbol;

  const CarnetType({
    required this.id,
    required this.code,
    required this.name,
    required this.size,
    required this.faceValue,
    required this.companyId,
    this.active = true,
    this.validityDays = 365,
    this.apiTotalAmount,
    this.currencyName = 'MRU',
    this.currencySymbol = '',
  });

  int get totalAmount => apiTotalAmount ?? (size * faceValue);

  String get displayCurrency {
    final c = currencyName.trim();
    if (c.isNotEmpty) return c;
    final s = currencySymbol.trim();
    if (s.isNotEmpty) return s;
    return 'MRU';
  }

  @override
  List<Object?> get props => [
    id,
    code,
    name,
    size,
    faceValue,
    companyId,
    active,
    validityDays,
    apiTotalAmount,
    currencyName,
    currencySymbol,
  ];
}
