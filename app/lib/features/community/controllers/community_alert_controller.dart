import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/community_alert_model.dart';

class CommunityAlertController extends ChangeNotifier {
  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();

  bool isCommunityResponder = false;
  bool isMonitoring = false;
  List<CommunityAlertModel> activeAlerts = [];
  CommunityAlertModel? latestUnacknowledgedAlert;
  final Set<String> _dismissedAlertIds = {};

  Timer? _pollingTimer;
  Position? lastKnownPosition;

  CommunityAlertController() {
    _initialize();
  }

  Future<void> _initialize() async {
    final user = _supabaseService.currentUser;
    if (user != null) {
      isCommunityResponder = user.userMetadata?['is_community_responder'] as bool? ?? false;
      // Also check users profile table
      try {
        final profile = await _supabaseService.client
            .from('users')
            .select('is_community_responder')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['is_community_responder'] != null) {
          isCommunityResponder = profile['is_community_responder'] == true;
        }
      } catch (_) {}

      if (isCommunityResponder) {
        startMonitoring();
      }
    }
  }

  void startMonitoring() {
    isMonitoring = true;
    _pollingTimer?.cancel();
    // Immediate check
    checkNearbyAlerts();
    // Poll every 8 seconds for real-time 2km emergency awareness
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      checkNearbyAlerts();
    });
    notifyListeners();
  }

  void stopMonitoring() {
    isMonitoring = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    notifyListeners();
  }

  Future<void> toggleOptIn(bool optIn) async {
    isCommunityResponder = optIn;
    notifyListeners();

    final user = _supabaseService.currentUser;
    if (user != null) {
      try {
        await _supabaseService.toggleCommunityResponder(
          userId: user.id,
          optIn: optIn,
        );
      } catch (e) {
        debugPrint('[COMMUNITY] Toggle opt-in notice: $e');
      }
    }

    if (optIn) {
      startMonitoring();
    } else {
      stopMonitoring();
      activeAlerts.clear();
      latestUnacknowledgedAlert = null;
    }
  }

  Future<void> checkNearbyAlerts() async {
    final user = _supabaseService.currentUser;
    if (user == null || !isCommunityResponder) return;

    try {
      // 1. Get current GPS position
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        lastKnownPosition = pos;
      }
      final currentPos = lastKnownPosition;
      if (currentPos == null) return;

      final lat = currentPos.latitude;
      final lng = currentPos.longitude;

      // 2. Sync responder location to backend
      _syncResponderLocation(user.id, lat, lng, currentPos.accuracy);

      // 3. Query active community alerts within 2 km (2000 meters)
      List<CommunityAlertModel> fetchedAlerts = [];

      // A. Try FastAPI backend endpoint
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final uri = Uri.parse(
          '$backendBase/responders/alerts?user_id=${user.id}&lat=$lat&lng=$lng&radius_m=2000.0',
        );
        final res = await http.get(
          uri,
          headers: {'ngrok-skip-browser-warning': 'true'},
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = (data['alerts'] as List?) ?? [];
          fetchedAlerts = list.map((e) => CommunityAlertModel.fromJson(e)).toList();
        }
      } catch (beError) {
        debugPrint('[COMMUNITY] Backend fetch notice: $beError, checking direct database');
      }

      // B. Fallback: Query direct Supabase panic_events if backend call was empty or failed
      if (fetchedAlerts.isEmpty) {
        try {
          final rows = await _supabaseService.client
              .from('panic_events')
              .select('id, user_id, latitude, longitude, trigger_method, triggered_at, status')
              .eq('status', 'active')
              .neq('user_id', user.id)
              .order('triggered_at', ascending: false)
              .limit(10);

          for (final row in (rows as List)) {
            final evLat = (row['latitude'] as num?)?.toDouble();
            final evLng = (row['longitude'] as num?)?.toDouble();
            if (evLat != null && evLng != null) {
              final dist = _calculateHaversineDistance(lat, lng, evLat, evLng);
              // Only within 2 km radius
              if (dist <= 2000.0) {
                // Get display name
                String displayName = 'SafeLink User';
                try {
                  final u = await _supabaseService.client
                      .from('users')
                      .select('full_name')
                      .eq('id', row['user_id'])
                      .maybeSingle();
                  if (u != null && u['full_name'] != null) {
                    final full = u['full_name'].toString().trim();
                    displayName = full.isNotEmpty ? full.split(' ')[0] : 'SafeLink User';
                  }
                } catch (_) {}

                fetchedAlerts.add(
                  CommunityAlertModel(
                    panicEventId: row['id'],
                    userName: displayName,
                    latitude: evLat,
                    longitude: evLng,
                    distanceMeters: dist,
                    mapsLink: 'https://www.google.com/maps/search/?api=1&query=$evLat,$evLng',
                    triggerMethod: row['trigger_method'] ?? 'emergency',
                    triggeredAt: row['triggered_at'] != null
                        ? (DateTime.tryParse(row['triggered_at'].toString()) ?? DateTime.now())
                        : DateTime.now(),
                    status: row['status'] ?? 'active',
                  ),
                );
              }
            }
          }
        } catch (sbError) {
          debugPrint('[COMMUNITY] Supabase direct alerts query notice: $sbError');
        }
      }

      activeAlerts = fetchedAlerts;

      // 4. Check if there is an unacknowledged and undismissed alert within 2 km
      final pendingAlert = activeAlerts.firstWhere(
        (a) => !_dismissedAlertIds.contains(a.panicEventId),
        orElse: () => CommunityAlertModel(
          panicEventId: '',
          userName: '',
          latitude: 0,
          longitude: 0,
          distanceMeters: 0,
          mapsLink: '',
          triggerMethod: '',
          triggeredAt: DateTime.now(),
          status: '',
        ),
      );

      if (pendingAlert.panicEventId.isNotEmpty &&
          (latestUnacknowledgedAlert?.panicEventId != pendingAlert.panicEventId)) {
        latestUnacknowledgedAlert = pendingAlert;
        _triggerAudibleAndVibratoryDistressAlert();
      } else if (pendingAlert.panicEventId.isEmpty) {
        latestUnacknowledgedAlert = null;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[COMMUNITY] Error checking nearby alerts: $e');
    }
  }

  void _syncResponderLocation(String userId, double lat, double lng, double accuracy) async {
    try {
      final backendBase = await AppConstants.getEffectiveBackendUrl();
      final uri = Uri.parse('$backendBase/responders/location');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'user_id': userId,
          'latitude': lat,
          'longitude': lng,
          'accuracy_m': accuracy,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Fallback: save directly to realtime_gps_logs
      try {
        await _supabaseService.client.from('realtime_gps_logs').insert({
          'user_id': userId,
          'latitude': lat,
          'longitude': lng,
          'accuracy_m': accuracy,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  void _triggerAudibleAndVibratoryDistressAlert() async {
    // 1. Heavy haptic vibration pulse
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // SOS rhythm vibration: 500ms on, 200ms off, 500ms on
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 800]);
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }

    // 2. System emergency sound alert
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> respondToAlert(String panicEventId) async {
    final user = _supabaseService.currentUser;
    if (user != null) {
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final uri = Uri.parse('$backendBase/responders/alerts/$panicEventId/respond?user_id=${user.id}');
        await http.post(uri, headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Direct Supabase fallback
        try {
          await _supabaseService.client.from('responder_alerts').upsert({
            'panic_event_id': panicEventId,
            'responder_id': user.id,
            'acknowledged_at': DateTime.now().toIso8601String(),
          }, onConflict: 'panic_event_id,responder_id');
        } catch (_) {}
      }
    }

    _dismissedAlertIds.add(panicEventId);
    latestUnacknowledgedAlert = null;
    notifyListeners();
  }

  void dismissAlert(String panicEventId) {
    _dismissedAlertIds.add(panicEventId);
    if (latestUnacknowledgedAlert?.panicEventId == panicEventId) {
      latestUnacknowledgedAlert = null;
    }
    notifyListeners();
  }

  /// Generates a realistic simulated 2 km distress notification
  /// so that the user can verify their phone's siren, vibration, and responder dialog.
  void simulateTestAlert() {
    final double baseLat = lastKnownPosition?.latitude ?? -1.2825;
    final double baseLng = lastKnownPosition?.longitude ?? 36.8222;

    final testId = 'test-alert-${DateTime.now().millisecondsSinceEpoch}';
    final testAlert = CommunityAlertModel(
      panicEventId: testId,
      userName: 'Test Distress Alert',
      latitude: baseLat + 0.0021,
      longitude: baseLng + 0.0018,
      distanceMeters: 310.0,
      mapsLink: 'https://www.google.com/maps/search/?api=1&query=${baseLat + 0.0021},${baseLng + 0.0018}',
      triggerMethod: 'shake',
      triggeredAt: DateTime.now(),
      status: 'active',
    );

    activeAlerts.removeWhere((a) => a.panicEventId.startsWith('test-alert-'));
    activeAlerts.insert(0, testAlert);
    latestUnacknowledgedAlert = testAlert;

    // Trigger siren tone and SOS vibration
    _triggerAudibleAndVibratoryDistressAlert();
    notifyListeners();
  }

  double _calculateHaversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000; // Earth's radius in meters
    final double phi1 = lat1 * pi / 180;
    final double phi2 = lat2 * pi / 180;
    final double deltaPhi = (lat2 - lat1) * pi / 180;
    final double deltaLambda = (lng2 - lng1) * pi / 180;

    final double a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return r * c;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
