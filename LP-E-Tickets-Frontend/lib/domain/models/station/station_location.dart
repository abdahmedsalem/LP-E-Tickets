import 'package:latlong2/latlong.dart';

/// Station affichable sur la carte et dans la liste de proximité.
class StationLocationItem {
  const StationLocationItem({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.phone,
    required this.location,
    this.is24h = true,
  });

  final String id;
  final String name;
  final String city;
  final String address;
  final String phone;
  final LatLng location;
  final bool is24h;
}
