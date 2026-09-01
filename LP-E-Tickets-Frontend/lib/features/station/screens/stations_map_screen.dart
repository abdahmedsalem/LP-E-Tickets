import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_url_opener.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_card.dart';

class StationLocationItem {
  final String id;
  final String name;
  final String city;
  final String address;
  final String phone;
  final LatLng location;
  final bool is24h;

  const StationLocationItem({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.phone,
    required this.location,
    this.is24h = true,
  });
}

class StationsMapScreen extends StatefulWidget {
  const StationsMapScreen({super.key});

  @override
  State<StationsMapScreen> createState() => _StationsMapScreenState();
}

class _StationsMapScreenState extends State<StationsMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  StationLocationItem? _selectedStation;
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
      final res = await OdooJsonRpcClient().postJsonRpc(
        path: '/api/acpec/fueltoken/v1/mobile/stations/list',
      );
      List<dynamic>? rawItems;
      if (res is Map) {
        final top = Map<String, dynamic>.from(res);
        final data = top['data'];
        if (data is Map && data['items'] is List) {
          rawItems = data['items'] as List;
        } else if (data is List) {
          rawItems = data;
        } else if (top['items'] is List) {
          rawItems = top['items'] as List;
        }
      } else if (res is List) {
        rawItems = res;
      }

      if (rawItems != null) {
        final list = <StationLocationItem>[];
        for (final item in rawItems) {
          if (item is! Map) continue;
          final row = Map<String, dynamic>.from(item);
          var lat = (row['latitude'] as num?)?.toDouble() ?? 0.0;
          var lng = (row['longitude'] as num?)?.toDouble() ?? 0.0;
          if (lat == 0.0 && lng == 0.0) {
            lat = 18.0858;
            lng = -15.9785;
          }
          final addr = row['address']?.toString() ?? 'Mauritanie';
          final city = addr.toLowerCase().contains('nouadhibou')
              ? 'Nouadhibou'
              : (addr.toLowerCase().contains('rosso') ? 'Rosso' : 'Nouakchott');
          list.add(
            StationLocationItem(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? 'Station Leader Petroleum',
              city: city,
              address: addr,
              phone: row['phone']?.toString() ?? '',
              location: LatLng(lat, lng),
            ),
          );
        }
        if (mounted) {
          setState(() {
            _backendStations = list;
            _hasFetchedBackend = true;
          });
        }
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
    final meters = const Distance().as(LengthUnit.Meter, center, stationLocation);
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  List<StationLocationItem> get _filteredStations {
    var list = List<StationLocationItem>.from(_allActiveStations);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((st) {
        return st.name.toLowerCase().contains(q) ||
            st.city.toLowerCase().contains(q) ||
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

  void _selectStation(StationLocationItem station) {
    setState(() {
      _selectedStation = station;
      _showListView = false;
    });
    _mapController.move(station.location, 14.8);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedStations = _filteredStations;

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
                  setState(() => _selectedStation = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.leaderpetroleum.etickets',
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
                                  hintText: 'Chercher une station Leader...',
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
            bottom: _selectedStation != null ? 220 : 32,
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
                    setState(() => _selectedStation = null);
                    _mapController.move(_initialCenter, 12.5);
                  },
                ),
              ],
            ),
          ),

          // 4. FICHE STATION STYLE GOOGLE MAPS
          if (_selectedStation != null && !_showListView)
            Positioned(
              left: 14,
              right: 14,
              bottom: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.leaderGreen.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _selectedStation!.city.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.leaderGreenDark,
                              letterSpacing: 0.5,
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
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Ouvert 24/7',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
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
                                _formattedDistanceTo(_selectedStation!.location),
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
                        InkWell(
                          onTap: () => setState(() => _selectedStation = null),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedStation!.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: AppColors.leaderGreenDark,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedStation!.address,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openMapsGps(_selectedStation!),
                            icon: const Icon(
                              Icons.directions_rounded,
                              size: 20,
                            ),
                            label: const Text(
                              'Itinéraire Google Maps',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.leaderGreen,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        if (_selectedStation!.phone.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: () =>
                                _callStation(_selectedStation!.phone),
                            icon: const Icon(Icons.phone_in_talk_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.surfaceContainerHighest,
                              foregroundColor: scheme.onSurface,
                              padding: const EdgeInsets.all(14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
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
                          'STATIONS LEADER PETROLEUM (${displayedStations.length})',
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
                          label: const Text('Retour carte'),
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
                                    st.city.toUpperCase(),
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
                                const Text(
                                  'Ouvert 24/7',
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
                              st.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              st.address,
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
                                    label: const Text('Voir sur carte'),
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
                                  label: const Text('GPS'),
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
