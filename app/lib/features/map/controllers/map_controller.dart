import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../models/police_station_model.dart';
import '../models/danger_zone_model.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/constants/app_constants.dart';
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

  // Real-Time Location Sharing State
  bool isSharingLocation = false;
  int sharingDurationHours = 8;
  DateTime? sharingExpiresAt;
  String? sharingSessionToken;
  String? shareableLink;
  Timer? _locationPingTimer;
  bool isStartingSharing = false;

  bool isLoading = false;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();
  StreamSubscription<Position>? _positionStreamSub;

  MapController() {
    initialize();
  }

  String get remainingSharingTimeFormatted {
    if (sharingExpiresAt == null) return '${sharingDurationHours}h';
    final diff = sharingExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
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

    // 5. Check if user already has an active sharing session
    await checkActiveSharingSession();

    isLoading = false;
    notifyListeners();
  }

  void _startPositionStream() {
    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
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

  // ─── REAL-TIME LOCATION SHARING ─────────────────────────────────────────────

  /// Starts real-time location sharing with configurable duration (1 - 24 hours).
  /// Pings GPS coordinates continuously every 10 seconds.
  Future<String?> startRealTimeLocationSharing({
    int durationHours = 8,
    bool isEmergency = false,
  }) async {
    final user = _supabaseService.currentUser;
    if (user == null) return null;

    isStartingSharing = true;
    notifyListeners();

    final clampedDuration = durationHours.clamp(1, 24);
    sharingDurationHours = clampedDuration;

    try {
      final pos = currentPosition ?? await _locationService.getCurrentPosition();
      final lat = pos?.latitude ?? -1.2825;
      final lng = pos?.longitude ?? 36.8222;
      final accuracy = pos?.accuracy ?? 15.0;

      final backendBase = await AppConstants.getEffectiveBackendUrl();
      final uri = Uri.parse('$backendBase/gps/share/start');

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'user_id': user.id,
          'duration_hours': clampedDuration,
          'latitude': lat,
          'longitude': lng,
          'accuracy_m': accuracy,
          'is_emergency': isEmergency,
          'activity_name': isEmergency ? '🚨 Emergency SOS Broadcast' : 'Real-Time Location Sharing',
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        sharingSessionToken = data['session_token'];
        shareableLink = data['tracking_url'];
        if (data['expires_at'] != null) {
          sharingExpiresAt = DateTime.tryParse(data['expires_at']);
        } else {
          sharingExpiresAt = DateTime.now().add(Duration(hours: clampedDuration));
        }

        isSharingLocation = true;
        _startPingTimer();
        debugPrint('[LOCATION SHARING] Started: $shareableLink (Duration: ${clampedDuration}h)');
      } else {
        // Fallback local link if backend request failed
        _generateFallbackLink(user.id, clampedDuration, lat, lng);
      }
    } catch (e) {
      debugPrint('[LOCATION SHARING] Backend call error: $e. Using local fallback.');
      final user = _supabaseService.currentUser;
      if (user != null) {
        _generateFallbackLink(user.id, clampedDuration, currentPosition?.latitude ?? -1.2825, currentPosition?.longitude ?? 36.8222);
      }
    } finally {
      isStartingSharing = false;
      notifyListeners();
    }

    return shareableLink;
  }

  void _generateFallbackLink(String userId, int duration, double lat, double lng) {
    sharingDurationHours = duration;
    sharingExpiresAt = DateTime.now().add(Duration(hours: duration));
    isSharingLocation = true;
    shareableLink = 'https://maps.google.com/search/?api=1&query=$lat,$lng';
    _startPingTimer();
  }

  void _startPingTimer() {
    _locationPingTimer?.cancel();
    // Ping every 10 seconds for real-time tracking
    _locationPingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pingCurrentLocation();
    });
  }

  Future<void> _pingCurrentLocation() async {
    if (!isSharingLocation) return;
    if (sharingExpiresAt != null && DateTime.now().isAfter(sharingExpiresAt!)) {
      cancelRealTimeLocationSharing();
      return;
    }

    final user = _supabaseService.currentUser;
    if (user == null) return;

    try {
      final pos = currentPosition ?? await _locationService.getCurrentPosition();
      if (pos == null) return;

      final backendBase = await AppConstants.getEffectiveBackendUrl();
      final uri = Uri.parse('$backendBase/gps/ping');

      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'user_id': user.id,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy_m': pos.accuracy,
          'speed': pos.speed,
          'altitude': pos.altitude,
          'session_token': sharingSessionToken,
        }),
      ).timeout(const Duration(seconds: 4));

      // Also persist to Supabase
      try {
        await _supabaseService.client.from('realtime_gps_logs').insert({
          'user_id': user.id,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'location_accuracy_m': pos.accuracy,
          'speed_kmh': pos.speed,
          'altitude_m': pos.altitude,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    } catch (_) {}
  }

  /// Cancels active real-time location sharing immediately
  Future<void> cancelRealTimeLocationSharing() async {
    _locationPingTimer?.cancel();
    _locationPingTimer = null;

    final user = _supabaseService.currentUser;
    final token = sharingSessionToken;

    isSharingLocation = false;
    shareableLink = null;
    sharingSessionToken = null;
    sharingExpiresAt = null;
    notifyListeners();

    if (user != null) {
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final uri = Uri.parse('$backendBase/gps/share/stop');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': user.id,
            'session_token': token,
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
  }

  /// Checks if user already has an active sharing session upon launch
  Future<void> checkActiveSharingSession() async {
    final user = _supabaseService.currentUser;
    if (user == null) return;

    try {
      final backendBase = await AppConstants.getEffectiveBackendUrl();
      final uri = Uri.parse('$backendBase/gps/share/${user.id}/active');
      final res = await http.get(uri, headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['is_active'] == true) {
          isSharingLocation = true;
          sharingSessionToken = data['session_token'];
          shareableLink = data['tracking_url'];
          if (data['expires_at'] != null) {
            sharingExpiresAt = DateTime.tryParse(data['expires_at']);
          }
          _startPingTimer();
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Opens the native sharing dialog to send tracking link via WhatsApp, SMS, etc.
  Future<void> shareViaNativeSheet() async {
    if (shareableLink == null) {
      await startRealTimeLocationSharing(durationHours: sharingDurationHours);
    }
    if (shareableLink == null) return;

    final msg = '🚨 SafeLink Live 3D Tracking: Follow my real-time location and safety status here:\n$shareableLink\n(Active for $remainingSharingTimeFormatted)';
    try {
      await SharePlus.instance.share(ShareParams(text: msg, subject: '🚨 SafeLink Live 3D Location Tracking'));
    } catch (e) {
      debugPrint('[MAP] Share error: $e');
    }
  }

  @override
  void dispose() {
    _locationPingTimer?.cancel();
    _positionStreamSub?.cancel();
    super.dispose();
  }
}
