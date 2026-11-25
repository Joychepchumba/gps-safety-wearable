import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('[LocationService] getLastKnownPosition error: $e');
      return null;
    }
  }

  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('[LocationService] isLocationServiceEnabled error: $e');
      return false;
    }
  }

  Future<LocationPermission> checkPermissionStatus() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('[LocationService] checkPermissionStatus error: $e');
      return LocationPermission.denied;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] Location service disabled on device');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('[LocationService] requestPermission error: $e');
      return false;
    }
  }

  Future<Position?> getCurrentPosition({
    bool preferCached = false,
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 8),
  }) async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] Service not enabled, checking last known position');
        return await Geolocator.getLastKnownPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        debugPrint('[LocationService] Permission not granted: $permission');
        return await Geolocator.getLastKnownPosition();
      }

      if (preferCached) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp).inMinutes < 2) {
          return lastKnown;
        }
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: timeLimit,
          ),
        );
      } catch (locErr) {
        debugPrint('[LocationService] getCurrentPosition timed out or failed: $locErr, trying last known');
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;
        // Fallback with lower accuracy if high accuracy failed
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[LocationService] Error fetching position: $e');
      return null;
    }
  }

  /// Streams position updates. Default distanceFilter is 15 meters to prevent micro-movements
  /// from waking the application CPU continuously while stationary.
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 15,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }

  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('[LocationService] openLocationSettings error: $e');
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[LocationService] openAppSettings error: $e');
      return false;
    }
  }

  Future<void> saveGpsLog(String panicEventId, Position pos, String userId) async {
    final nowIso = DateTime.now().toIso8601String();
    
    // 1. Insert into realtime_gps_logs table
    try {
      await _client.from('realtime_gps_logs').insert({
        'panic_event_id': panicEventId,
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_m': pos.accuracy,
        'recorded_at': nowIso,
      });
    } catch (e) {
      debugPrint('[LocationService] Error saving to realtime_gps_logs: $e');
    }

    // 2. Insert into locations table
    try {
      await _client.from('locations').insert({
        'panic_event_id': panicEventId,
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_m': pos.accuracy,
        'recorded_at': nowIso,
        'is_anonymised': false,
      });
    } catch (e) {
      debugPrint('[LocationService] Note: saving to locations table: $e');
    }

    // 3. Update users table with current location
    try {
      await _client.from('users').update({
        'last_latitude': pos.latitude,
        'last_longitude': pos.longitude,
        'last_location_updated_at': nowIso,
        'is_location_anonymised': false,
      }).eq('id', userId);
    } catch (e) {
      debugPrint('[LocationService] Note: updating users table location: $e');
    }
  }
}
