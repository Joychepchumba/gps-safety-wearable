import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  SupabaseClient get _client => Supabase.instance.client;

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
    try {
      await _client.from('realtime_gps_logs').insert({
        'panic_event_id': panicEventId,
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_m': pos.accuracy,
        'recorded_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[LocationService] Error saving GPS log: $e');
    }
  }
}
