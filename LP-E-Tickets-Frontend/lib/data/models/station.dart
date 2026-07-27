import 'package:equatable/equatable.dart';

/// acpec.fuel.station
class Station extends Equatable {
  final String id;
  final String code;
  final String name;
  final String address;
  final String companyId;
  final bool active;

  const Station({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.companyId,
    this.active = true,
  });

  @override
  List<Object?> get props => [id, code, name, companyId, active];
}
