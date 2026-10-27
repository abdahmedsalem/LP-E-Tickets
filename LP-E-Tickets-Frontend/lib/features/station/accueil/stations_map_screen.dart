import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_url_opener.dart';
import '../../../data/services/station_services/station_route_service.dart';
import '../../../domain/models/station/station_route.dart';
import '../../../domain/models/station/station_location.dart';
import '../controllers/station_controller.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../l10n/app_localizations.dart';

class StationsMapScreen extends StatefulWidget {
  const StationsMapScreen({super.key, required this.controller});

  final StationController controller;

  @override
  State<StationsMapScreen> createState() => _StationsMapScreenState();
}

class _StationsMapScreenState extends State<StationsMapScreen> {
  StationController get _stationController => widget.controller;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  StationLocationItem? _selectedStation;
  final StationRouteService _stationRouteService = StationRouteService();
  LatLng? _deviceLocation;
  StationRoute? _selectedRoute;
  int _routeRequestId = 0;
  bool _isRouteLoading = false;
  bool _showListView = false;
  List<StationLocationItem> _backendStations = [];
  bool _hasFetchedBackend = false;

  static const List<StationLocationItem> _defaultStations = [
    StationLocationItem(
      id: 'st_ksar',
      name: 'Station LP Ksar',
      city: 'Nouakchott',
      address: 'Avenue Gamal Abdel Nasser, Le Ksar, Nouakchott',
      phone: '+222 45 25 20 20',
      location: LatLng(18.0872, -15.9680),
    ),
  ];

  static const LatLng _initialCenter = LatLng(18.0858, -15.9785);

  @override
  void initState() {
    super.initState();
    _fetchBackendStations();
  }

  Future<void> _fetchBackendStations() async {
    try {
      final stations = await _stationController.stations();
      if (mounted) {
        setState(() {
          _backendStations = stations;
          _hasFetchedBackend = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasFetchedBackend = false);
      }
    }
  }

  List<StationLocationItem> get _allActiveStations =>
      _hasFetchedBackend ? _backendStations : _defaultStations;

  LatLng get _currentCenter {
    try {
      return _mapController.camera.center;
    } catch (_) {
      return _initialCenter;
    }
  }

  String _formattedDistanceTo(LatLng stationLocation) {
    final center = _currentCenter;
    final meters = const Distance().as(
      LengthUnit.Meter,
      center,
      stationLocation,
    );
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  List<StationLocationItem> _filteredStations(AppLocalizations l10n) {
    var list = List<StationLocationItem>.from(_allActiveStations);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((st) {
        return st.name.toLowerCase().contains(q) ||
            st.city.toLowerCase().contains(q) ||
            _localizedCity(st.city, l10n).toLowerCase().contains(q) ||
            st.address.toLowerCase().contains(q);
      }).toList();
    }
    final center = _currentCenter;
    list.sort((a, b) {
      final distA = const Distance().as(LengthUnit.Meter, center, a.location);
      final distB = const Distance().as(LengthUnit.Meter, center, b.location);
      return distA.compareTo(distB);
    });
    return list;
  }

  String _localizedCity(String city, AppLocalizations l10n) {
    switch (city.trim().toLowerCase()) {
      case 'nouakchott':
        return l10n.stationCityNouakchott;
      case 'nouadhibou':
        return l10n.stationCityNouadhibou;
      case 'rosso':
        return l10n.stationCityRosso;
      default:
        return city;
    }
  }

  String _localizedStationName(
    StationLocationItem station,
    AppLocalizations l10n,
  ) {
    if (station.id == 'st_ksar' || station.name == 'Station Leader Petroleum') {
      return l10n.stationDefaultName;
    }
    return station.name;
  }

  String _localizedAddress(StationLocationItem station, AppLocalizations l10n) {
    return station.address.trim().isEmpty
        ? l10n.stationCountryMauritania
        : station.address;
  }

  void _selectStation(StationLocationItem station) {
    final requestId = ++_routeRequestId;
    setState(() {
      _selectedStation = station;
      _deviceLocation = null;
      _selectedRoute = null;
      _isRouteLoading = true;
      _showListView = false;
    });
    _mapController.move(station.location, 14.8);
    unawaited(_loadRouteFromCurrentLocation(station, requestId));
  }

  void _clearSelectedStation() {
    _routeRequestId++;
    setState(() {
      _selectedStation = null;
      _deviceLocation = null;
      _selectedRoute = null;
      _isRouteLoading = false;
    });
  }

  Future<void> _loadRouteFromCurrentLocation(
    StationLocationItem station,
    int requestId,
  ) async {
    LatLng? origin;
    try {
      origin = await _getCurrentLocation();
    } catch (_) {
      origin = null;
    }

    if (!mounted || requestId != _routeRequestId) return;
    if (origin == null) {
      setState(() => _isRouteLoading = false);
      _showMapMessage(
        AppLocalizations.of(context).stationLocationPermissionRequired,
      );
      return;
    }

    setState(() => _deviceLocation = origin);

    StationRoute? route;
    try {
      route = await _stationRouteService.getDrivingRoute(
        origin: origin,
        destination: station.location,
      );
    } catch (_) {
      route = null;
    }

    if (!mounted || requestId != _routeRequestId) return;
    setState(() {
      _selectedRoute = route;
      _isRouteLoading = false;
    });

    if (route == null) {
      _showMapMessage(AppLocalizations.of(context).stationRouteUnavailable);
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route.points),
        padding: const EdgeInsets.fromLTRB(36, 132, 36, 240),
      ),
    );
  }

  Future<LatLng?> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  void _showMapMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _routeSummary(AppLocalizations l10n, StationRoute route) {
    final distance = (route.distanceMeters / 1000).toStringAsFixed(1);
    final duration = (route.durationSeconds / 60).round().toString();
    return l10n.stationRouteSummary(distance, duration);
  }

  Future<void> _openMapsGps(StationLocationItem station) async {
    final googleMapsDirUrl =
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${station.location.latitude},${station.location.longitude}'
        '&travelmode=driving&dir_action=navigate';
    final googleMapsSearchUrl =
        'https://www.google.com/maps/search/?api=1&query=${station.location.latitude},${station.location.longitude}';

    var opened = await openExternalUrl(googleMapsDirUrl);
    if (!opened) {
      await openExternalUrl(googleMapsSearchUrl);
    }
  }

  Future<void> _callStation(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanPhone.isEmpty) return;
    await openExternalUrl('tel:$cleanPhone');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    _stationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final displayedStations = _filteredStations(l10n);

    return Scaffold(
      body: Stack(
        children: [
          // 1. CARTE STYLE GOOGLE MAPS RETINA
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 12.5,
              minZoom: 5.0,
              maxZoom: 18.0,
              onTap: (tapPosition, point) {
                if (_selectedStation != null) {
                  _clearSelectedStation();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.leaderpetroleum.etickets',
              ),
              if (_selectedRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _selectedRoute!.points,
                      color: const Color(0xFF3478F6),
                      strokeWidth: 6,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: displayedStations.map((st) {
                  final isSelected = _selectedStation?.id == st.id;
                  return Marker(
                    point: st.location,
                    width: isSelected ? 80 : 54,
                    height: isSelected ? 80 : 54,
                    child: GestureDetector(
                      onTap: () => _selectStation(st),
                      child: _GoogleMapsStyleMarker(
                        station: st,
                        isSelected: isSelected,
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_deviceLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _deviceLocation!,
                      width: 104,
                      height: 68,
                      alignment: Alignment.bottomCenter,
                      child: _RouteOriginMarker(
                        routeSummary: _selectedRoute == null
                            ? null
                            : _routeSummary(l10n, _selectedRoute!),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. EN-TÊTE FLOTTANT STYLE GOOGLE MAPS
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.90),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: AppColors.ink,
                                size: 19,
                              ),
                              onPressed: () => context.pop(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: l10n.stationSearchPlaceholder,
                                  hintStyle: TextStyle(
                                    fontSize: 13.5,
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: AppColors.leaderGreenDark,
                                    size: 22,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _showListView
                                  ? AppColors.leaderGreen
                                  : Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                _showListView
                                    ? Icons.map_rounded
                                    : Icons.format_list_bulleted_rounded,
                                color: _showListView
                                    ? Colors.white
                                    : AppColors.ink,
                              ),
                              onPressed: () {
                                setState(() => _showListView = !_showListView);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. BOUTONS DE ZOOM ET DE RECENTRAGE
          Positioned(
            right: 16,
            bottom: _selectedStation != null ? 240 : 32,
            child: Column(
              children: [
                _MapControlButton(
                  icon: Icons.add_rounded,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _MapControlButton(
                  icon: Icons.remove_rounded,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _MapControlButton(
                  icon: Icons.my_location_rounded,
                  accentColor: AppColors.leaderGreenDark,
                  onPressed: () {
                    _clearSelectedStation();
                    _mapController.move(_initialCenter, 12.5);
                  },
                ),
              ],
            ),
          ),

          // 4. Station preview card over the map.
          if (_selectedStation != null && !_showListView)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F1),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.local_gas_station_rounded,
                            size: 42,
                            color: AppColors.leaderGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _localizedStationName(
                                        _selectedStation!,
                                        l10n,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        height: 1.15,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: _clearSelectedStation,
                                    borderRadius: BorderRadius.circular(18),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 19,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _StationInfoChip(
                                    icon: Icons.location_city_rounded,
                                    label: _localizedCity(
                                      _selectedStation!.city,
                                      l10n,
                                    ),
                                  ),
                                  if (_selectedStation!.is24h)
                                    _StationInfoChip(
                                      icon: Icons.schedule_rounded,
                                      label: l10n.stationOpen247,
                                      color: const Color(0xFF15803D),
                                      backgroundColor: const Color(0xFFDCFCE7),
                                    ),
                                ],
                              ),
                              if (_isRouteLoading) ...[
                                const SizedBox(height: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF3478F6),
                                  ),
                                ),
                              ] else if (_selectedRoute != null) ...[
                                const SizedBox(height: 7),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.near_me_rounded,
                                      size: 14,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _routeSummary(l10n, _selectedRoute!),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: AppColors.leaderGreenDark,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _localizedAddress(_selectedStation!, l10n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: l10n.stationDirectionsGoogleMaps,
                          onPressed: () => _openMapsGps(_selectedStation!),
                          icon: const Icon(Icons.navigation_rounded, size: 19),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.leaderGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(42, 42),
                          ),
                        ),
                        if (_selectedStation!.phone.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            onPressed: () =>
                                _callStation(_selectedStation!.phone),
                            icon: const Icon(
                              Icons.phone_in_talk_rounded,
                              size: 19,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.surfaceContainerHighest,
                              foregroundColor: scheme.onSurface,
                              minimumSize: const Size(42, 42),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // 5. VUE LISTE SI APPUYÉ SUR LE BOUTON COMMUTATEUR
          if (_showListView)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).padding.top + 115,
              bottom: 0,
              child: Container(
                color: const Color(0xFFF8FAFC),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.stationListTitle(displayedStations.length),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.8,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showListView = false),
                          icon: const Icon(Icons.map_rounded, size: 18),
                          label: Text(l10n.stationBackToMap),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final st in displayedStations) ...[
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        radius: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.leaderGreen.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _localizedCity(st.city, l10n).toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.leaderGreenDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.near_me_rounded,
                                        size: 12,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formattedDistanceTo(st.location),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  l10n.stationOpen247,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _localizedStationName(st, l10n),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _localizedAddress(st, l10n),
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _selectStation(st),
                                    icon: const Icon(
                                      Icons.center_focus_strong_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l10n.stationViewOnMap),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          AppColors.leaderGreenDark,
                                      side: const BorderSide(
                                        color: AppColors.leaderGreen,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: () => _openMapsGps(st),
                                  icon: const Icon(
                                    Icons.directions_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.stationGps),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.leaderGreen,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteOriginMarker extends StatelessWidget {
  const _RouteOriginMarker({this.routeSummary});

  final String? routeSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (routeSummary != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              routeSummary!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF3478F6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_car_filled_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
      ],
    );
  }
}

class _StationInfoChip extends StatelessWidget {
  const _StationInfoChip({
    required this.icon,
    required this.label,
    this.color = AppColors.leaderGreenDark,
    this.backgroundColor = const Color(0xFFEAF4EC),
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleMapsStyleMarker extends StatelessWidget {
  final StationLocationItem station;
  final bool isSelected;

  const _GoogleMapsStyleMarker({
    required this.station,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.18 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [const Color(0xFF15803D), AppColors.leaderGreen]
                    : [const Color(0xFF0F172A), const Color(0xFF334155)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? AppColors.leaderGreen : Colors.black)
                      .withValues(alpha: 0.40),
                  blurRadius: isSelected ? 14 : 6,
                  spreadRadius: isSelected ? 3 : 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              width: isSelected ? 26 : 22,
              height: isSelected ? 26 : 22,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Image.asset(
                  'assets/images/logo_fueltoken_launcher.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? accentColor;

  const _MapControlButton({
    required this.icon,
    required this.onPressed,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(icon, color: accentColor ?? AppColors.ink, size: 20),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
