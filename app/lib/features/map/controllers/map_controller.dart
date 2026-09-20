import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/di/service_locator.dart';

class MapController extends ChangeNotifier {
  Position? currentPosition;
  List<Map<String, dynamic>> nearbyResponders = [];
  PanicEventModel? activeAlert;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();

  MapController() {
    initialize();
  }

  Future<void> initialize() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        currentPosition = pos;
      } else {
        // Fallback default coordinates (Nairobi)
        currentPosition = Position(
          latitude: -1.2921,
          longitude: 36.8219,
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
        latitude: -1.2921,
        longitude: 36.8219,
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
    notifyListeners();
    await loadNearbyResponders();
  }

  Future<void> loadNearbyResponders() async {
    try {
      final res = await _supabaseService.client
          .from('users')
          .select('id, full_name, is_community_responder, responder_status')
          .eq('is_community_responder', true)
          .eq('responder_status', 'available');

      nearbyResponders = (res as List).map((u) => {
        'id': u['id'],
        'name': u['full_name'],
        'lat': (currentPosition?.latitude ?? -1.2921) + 0.002,
        'lng': (currentPosition?.longitude ?? 36.8219) + 0.002,
        'distance': 250,
      }).toList();
    } catch (e) {
      debugPrint('Error loading responders: $e');
    }
    notifyListeners();
  }

  Future<void> startLocationSharing(List<String> contactIds) async {
    notifyListeners();
  }

  Future<void> stopLocationSharing() async {
    notifyListeners();
  }
}
