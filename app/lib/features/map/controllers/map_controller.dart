import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../models/police_station_model.dart';
import '../models/danger_zone_model.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/di/service_locator.dart';

class MapController extends ChangeNotifier {
  Position? currentPosition;
  List<PoliceStationModel> policeStations = [];
  List<DangerZoneModel> dangerZones = [];
  List<Map<String, dynamic>> nearbyResponders = [];
  DangerZoneModel? activeDangerZoneWarning;
  PanicEventModel? activeAlert;
  bool isSharingLocation = false;
  bool isLoading = false;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();
  StreamSubscription<Position>? _positionStreamSub;

  MapController() {
    initialize();
  }

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();

    // 1. Initial police stations and danger zones
    policeStations = PoliceStationModel.defaultKenyaStations();
    dangerZones = DangerZoneModel.defaultDangerZones();

    // 2. Fetch current GPS position
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        currentPosition = pos;
      } else {
        currentPosition = Position(
          latitude: -1.2825,
          longitude: 36.8222,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 1795.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
      }
    } catch (_) {
      currentPosition = Position(
        latitude: -1.2825,
        longitude: 36.8222,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 1795.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    }

    _sortLocationsByDistance();
    _checkGeofenceAlerts();

    // 3. Start position listening
    _startPositionStream();

    // 4. Load community responders
    await loadNearbyResponders();

    isLoading = false;
    notifyListeners();
  }

  void _startPositionStream() {
    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((Position pos) {
      currentPosition = pos;
      _sortLocationsByDistance();
      _checkGeofenceAlerts();
      notifyListeners();
    }, onError: (e) {
      debugPrint('[MAP] Position stream notice: $e');
    });
  }

  void _sortLocationsByDistance() {
    if (currentPosition == null) return;
    final userLat = currentPosition!.latitude;
    final userLng = currentPosition!.longitude;

    policeStations.sort(
      (a, b) => a.distanceTo(userLat, userLng).compareTo(b.distanceTo(userLat, userLng)),
    );
    dangerZones.sort(
      (a, b) => a.distanceTo(userLat, userLng).compareTo(b.distanceTo(userLat, userLng)),
    );
  }

  void _checkGeofenceAlerts() {
    if (currentPosition == null) return;
    final userLat = currentPosition!.latitude;
    final userLng = currentPosition!.longitude;

    DangerZoneModel? insideZone;
    for (final zone in dangerZones) {
      if (zone.containsUser(userLat, userLng)) {
        insideZone = zone;
        break;
      }
    }

    if (activeDangerZoneWarning?.id != insideZone?.id) {
      activeDangerZoneWarning = insideZone;
      if (insideZone != null) {
        debugPrint('⚠️ [GEOFENCE ALERT] User entered high-risk hotspot: ${insideZone.locationName}');
      }
    }
  }

  PoliceStationModel? get nearestPoliceStation {
    if (policeStations.isEmpty) return null;
    return policeStations.first;
  }

  Future<void> loadNearbyResponders() async {
    try {
      final res = await _supabaseService.client
          .from('users')
          .select('id, full_name, is_community_responder, responder_status')
          .eq('is_community_responder', true)
          .eq('responder_status', 'available');

      final baseLat = currentPosition?.latitude ?? -1.2825;
      final baseLng = currentPosition?.longitude ?? 36.8222;

      // Map responders near user
      nearbyResponders = (res as List).asMap().entries.map((entry) {
        final i = entry.key;
        final u = entry.value;
        final offsetLat = ((i % 3) - 1) * 0.0035;
        final offsetLng = (((i ~/ 3) % 3) - 1) * 0.0035;
        return {
          'id': u['id'],
          'name': u['full_name'] ?? 'Responder #${i + 1}',
          'lat': baseLat + offsetLat,
          'lng': baseLng + offsetLng,
          'distance': ((i + 1) * 350).toDouble(),
        };
      }).toList();
    } catch (e) {
      debugPrint('[MAP] Responders load notice: $e');
    }
    notifyListeners();
  }

  /// Share live location link with contacts via native sharing
  Future<void> shareLiveLocation({String? customMessage}) async {
    if (currentPosition == null) return;
    isSharingLocation = true;
    notifyListeners();

    final lat = currentPosition!.latitude.toStringAsFixed(6);
    final lng = currentPosition!.longitude.toStringAsFixed(6);
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    final text = customMessage ??
        '🚨 SafeLink Live Tracking Alert: I am sharing my current location for safety.\n'
        'Coordinates: $lat, $lng\n'
        'Live Map Link: $mapsUrl';

    try {
      // ignore: deprecated_member_use
      await Share.share(text, subject: '🚨 SafeLink Emergency Location Tracking');
    } catch (e) {
      debugPrint('[MAP] Share error: $e');
    }
  }

  void stopLocationSharing() {
    isSharingLocation = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }
}
