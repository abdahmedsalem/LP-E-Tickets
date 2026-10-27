import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/models/station/station_route.dart';

class StationRouteService {
  StationRouteService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  static const _routingHost = 'router.project-osrm.org';
  final Dio _dio;

  Future<StationRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    // The public OSRM service receives both coordinates to return road geometry.
    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.https(
      _routingHost,
      '/route/v1/driving/$coordinates',
      const {'overview': 'full', 'geometries': 'geojson'},
    );

    final response = await _dio.getUri<Map<String, dynamic>>(uri);
    final data = response.data;
    if (data == null || data['code'] != 'Ok') return null;

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      return null;
    }

    final route = Map<String, dynamic>.from(routes.first as Map);
    final geometry = route['geometry'];
    if (geometry is! Map || geometry['coordinates'] is! List) return null;

    final points = <LatLng>[];
    for (final coordinate in geometry['coordinates'] as List) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final longitude = coordinate[0];
      final latitude = coordinate[1];
      if (longitude is! num || latitude is! num) continue;
      points.add(LatLng(latitude.toDouble(), longitude.toDouble()));
    }

    final distance = route['distance'];
    final duration = route['duration'];
    if (points.length < 2 || distance is! num || duration is! num) {
      return null;
    }

    return StationRoute(
      points: points,
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
    );
  }
}
