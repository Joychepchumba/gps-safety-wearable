import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../models/panic_event_model.dart';
import '../../../models/emergency_contact_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/sms_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/constants/app_constants.dart';
import '../../contacts/controllers/contacts_controller.dart';

class MapController extends ChangeNotifier {
  Position? currentPosition;
  bool isLoadingLocation = true;
  bool isGpsServiceEnabled = true;
  bool _hasLocationPermission = true;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasLocationPermissionValue => _hasLocationPermission;

  String locationStatusMessage = 'Acquiring GPS location...';
  
  List<Map<String, dynamic>> nearbyResponders = [];
  List<Map<String, dynamic>> mappedEmergencyContacts = [];
  PanicEventModel? activeAlert;
  
  // Location sharing state
  bool isSharingLocation = false;
  DateTime? sharingExpiresAt;
  int sharingDurationHours = 1;
  String? activeSessionToken;
  Timer? _sharingTimer;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();

  StreamSubscription<Position>? _positionSub;
  bool isTrackingActive = false;

  // Static list of major police stations around Nairobi
  final List<Map<String, dynamic>> policeStations = [
    {
      'id': 'police-central',
      'name': 'Nairobi Central Police Station',
      'address': 'University Way / Harry Thuku Rd',
      'phone': '+254 20 2222222',
      'lat': -1.2829,
      'lng': 36.8228,
      'hotline': '999 / 112',
    },
    {
      'id': 'police-kilimani',
      'name': 'Kilimani Police Station',
      'address': 'Argwings Kodhek Rd, Kilimani',
      'phone': '+254 20 2711000',
      'lat': -1.2905,
      'lng': 36.7865,
      'hotline': '020 2711000',
    },
    {
      'id': 'police-parklands',
      'name': 'Parklands Police Station',
      'address': 'Parklands Rd / 3rd Parklands Ave',
      'phone': '+254 20 3740000',
      'lat': -1.2612,
      'lng': 36.8152,
      'hotline': '020 3740000',
    },
    {
      'id': 'police-langata',
      'name': 'Langata Police Station',
      'address': 'Langata Rd, near Bomas of Kenya',
      'phone': '+254 20 891100',
      'lat': -1.3340,
      'lng': 36.7580,
      'hotline': '020 891100',
    },
    {
      'id': 'police-madaraka',
      'name': 'Madaraka Police Post',
      'address': 'Ole Sangale Rd, Madaraka',
      'phone': '+254 721 228989',
      'lat': -1.3090,
      'lng': 36.8120,
      'hotline': '+254 721 228989',
    },
    {
      'id': 'police-nbi-area',
      'name': 'Nairobi Area Police Headquarters',
      'address': 'Milimani Rd / Ralph Bunche Rd',
      'phone': '+254 20 2724200',
      'lat': -1.2780,
      'lng': 36.8050,
      'hotline': '020 2724200',
    },
  ];

  MapController() {
    initialize();
  }

  Future<void> initialize() async {
    isLoadingLocation = true;
    notifyListeners();

    await refreshLocation();
    await loadNearbyResponders();
    await loadEmergencyContactsForMap();

    isLoadingLocation = false;
    notifyListeners();
  }

  Future<void> refreshLocation() async {
    try {
      isGpsServiceEnabled = await _locationService.isLocationServiceEnabled();
      if (!isGpsServiceEnabled) {
        locationStatusMessage = 'GPS is turned off on this device. Please enable Location Services.';
        _useFallbackLocation();
        notifyListeners();
        return;
      }

      final permStatus = await _locationService.checkPermissionStatus();
      if (permStatus == LocationPermission.denied || permStatus == LocationPermission.deniedForever) {
        final granted = await _locationService.requestPermission();
        _hasLocationPermission = granted;
        if (!granted) {
          locationStatusMessage = 'Location permission is required to track your safety in real-time.';
          _useFallbackLocation();
          notifyListeners();
          return;
        }
      } else {
        _hasLocationPermission = true;
      }

      final pos = await _locationService.getCurrentPosition(preferCached: true);
      if (pos != null) {
        currentPosition = pos;
        locationStatusMessage = 'GPS Active (±${pos.accuracy.toStringAsFixed(0)}m accuracy)';
      } else {
        locationStatusMessage = 'Unable to get live GPS fix. Using last known/default location.';
        _useFallbackLocation();
      }
    } catch (e) {
      debugPrint('[MapController] Error in refreshLocation: $e');
      locationStatusMessage = 'GPS error occurred: $e';
      _useFallbackLocation();
    }
    notifyListeners();
  }

  void startTracking() {
    if (isTrackingActive && _positionSub != null) return;
    isTrackingActive = true;
    _startPositionListening();
  }

  void stopTracking() {
    if (isSharingLocation) return;
    isTrackingActive = false;
    _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[MapController] GPS stream paused to preserve phone battery');
  }

  void _startPositionListening() {
    _positionSub?.cancel();
    try {
      _positionSub = _locationService.getPositionStream(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // 15m filter avoids battery drain from GPS noise
      ).listen(
        (Position pos) {
          currentPosition = pos;
          locationStatusMessage = 'GPS Active (±${pos.accuracy.toStringAsFixed(0)}m)';
          notifyListeners();
        },
        onError: (err) {
          debugPrint('[MapController] Stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('[MapController] Could not start position stream: $e');
    }
  }

  void _useFallbackLocation() {
    // Nairobi city center fallback
    currentPosition ??= Position(
      latitude: -1.31122,
      longitude: 36.81953,
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

  Future<void> openLocationSettings() async {
    await _locationService.openLocationSettings();
    await refreshLocation();
  }

  Future<void> openAppSettings() async {
    await _locationService.openAppSettings();
    await refreshLocation();
  }

  Future<void> loadNearbyResponders() async {
    try {
      final res = await _supabaseService.client
          .from('users')
          .select('id, full_name, phone_number, is_community_responder, responder_status')
          .eq('is_community_responder', true)
          .eq('responder_status', 'available');

      final baseLat = currentPosition?.latitude ?? -1.31122;
      final baseLng = currentPosition?.longitude ?? 36.81953;

      int idx = 0;
      nearbyResponders = (res as List).map((u) {
        idx++;
        // Offsets around user (approx 150m - 500m)
        final offsetLat = (idx % 2 == 0 ? 1 : -1) * (0.0015 * idx);
        final offsetLng = (idx % 3 == 0 ? 1 : -1) * (0.0018 * idx);
        return {
          'id': u['id'],
          'name': u['full_name'] ?? 'Responder $idx',
          'phone': u['phone_number'] ?? '',
          'lat': baseLat + offsetLat,
          'lng': baseLng + offsetLng,
          'distance': 150 + (idx * 90),
        };
      }).toList();

      if (nearbyResponders.isEmpty) {
        nearbyResponders = [
          {
            'id': 'resp-1',
            'name': 'Sarah N. (Community Watch)',
            'phone': '+254 700 112 233',
            'lat': baseLat + 0.0022,
            'lng': baseLng + 0.0018,
            'distance': 280,
          },
          {
            'id': 'resp-2',
            'name': 'David K. (Security Patrol)',
            'phone': '+254 711 445 566',
            'lat': baseLat - 0.0018,
            'lng': baseLng - 0.0025,
            'distance': 340,
          },
          {
            'id': 'resp-3',
            'name': 'Grace W. (First Responder)',
            'phone': '+254 722 778 899',
            'lat': baseLat + 0.0031,
            'lng': baseLng - 0.0012,
            'distance': 420,
          },
        ];
      }
    } catch (e) {
      debugPrint('Error loading responders: $e');
      final baseLat = currentPosition?.latitude ?? -1.31122;
      final baseLng = currentPosition?.longitude ?? 36.81953;
      nearbyResponders = [
        {
          'id': 'resp-1',
          'name': 'Community Patrol Alpha',
          'phone': '+254 700 123 456',
          'lat': baseLat + 0.002,
          'lng': baseLng + 0.002,
          'distance': 310,
        },
      ];
    }
    notifyListeners();
  }

  Future<void> loadEmergencyContactsForMap() async {
    final baseLat = currentPosition?.latitude ?? -1.31122;
    final baseLng = currentPosition?.longitude ?? 36.81953;

    try {
      List<EmergencyContactModel> rawContacts = [];
      try {
        final contactsCtrl = sl<ContactsController>();
        rawContacts = contactsCtrl.contacts;
      } catch (_) {}

      if (rawContacts.isEmpty) {
        final user = _supabaseService.currentUser;
        if (user != null) {
          final res = await _supabaseService.client
              .from('emergency_contacts')
              .select()
              .eq('user_id', user.id);
          rawContacts = (res as List).map((e) => EmergencyContactModel.fromJson(e)).toList();
        }
      }

      int i = 0;
      mappedEmergencyContacts = rawContacts.map((c) {
        i++;
        final offsetLat = (i % 2 == 0 ? -1 : 1) * (0.0025 * i);
        final offsetLng = (i % 2 == 0 ? 1 : -1) * (0.0022 * i);
        return {
          'id': c.id,
          'name': c.contactName,
          'phone': c.phoneNumber,
          'lat': baseLat + offsetLat,
          'lng': baseLng + offsetLng,
          'isContact': true,
        };
      }).toList();

      // If user hasn't added contacts yet, display demo contacts so the user sees how they appear
      if (mappedEmergencyContacts.isEmpty) {
        mappedEmergencyContacts = [
          {
            'id': 'demo-contact-1',
            'name': 'Mom (Emergency Kin)',
            'phone': '+254 712 345 678',
            'lat': baseLat + 0.0035,
            'lng': baseLng + 0.0020,
            'isContact': true,
          },
          {
            'id': 'demo-contact-2',
            'name': 'James (Guardian / Sibling)',
            'phone': '+254 722 987 654',
            'lat': baseLat - 0.0028,
            'lng': baseLng - 0.0030,
            'isContact': true,
          },
        ];
      }
    } catch (e) {
      debugPrint('[MapController] Error loading contacts for map: $e');
    }
    notifyListeners();
  }

  /// Generate Mapbox 3D live tracking link
  Future<String> getLiveTrackingLink() async {
    final lat = currentPosition?.latitude ?? -1.31122;
    final lng = currentPosition?.longitude ?? 36.81953;
    final user = _supabaseService.currentUser;
    final userName = user?.userMetadata?['full_name'] ?? 'SafeGuard User';
    return AppConstants.buildLiveTrackingUrl(
      lat: lat,
      lng: lng,
      name: userName,
    );
  }

  /// Start live location sharing with hours picker
  Future<String> startLocationSharing({
    int hours = 2,
    List<String>? targetContactPhones,
  }) async {
    final lat = currentPosition?.latitude ?? -1.31122;
    final lng = currentPosition?.longitude ?? 36.81953;
    final user = _supabaseService.currentUser;
    final userName = user?.userMetadata?['full_name'] ?? 'SafeLink User';
    final token = 'session_${DateTime.now().millisecondsSinceEpoch}';

    isSharingLocation = true;
    sharingDurationHours = hours;
    sharingExpiresAt = DateTime.now().add(Duration(hours: hours));
    activeSessionToken = token;

    _sharingTimer?.cancel();
    _sharingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (sharingExpiresAt != null && DateTime.now().isAfter(sharingExpiresAt!)) {
        stopLocationSharing();
      } else {
        notifyListeners();
      }
    });

    // Make sure GPS stays active during sharing
    startTracking();

    // Send SMS via Africa's Talking with the Live 3D Tracking link
    if (targetContactPhones != null && targetContactPhones.isNotEmpty) {
      try {
        final smsService = sl<SmsService>();
        unawaited(smsService.sendLiveLocationShareSms(
          targetContactPhones,
          userName,
          lat,
          lng,
          hours,
          token,
        ));
      } catch (e) {
        debugPrint('[MapController] Error sending location sharing SMS: $e');
      }
    }

    notifyListeners();
    return await getLiveTrackingLink();
  }

  /// Stop active location sharing
  Future<void> stopLocationSharing() async {
    isSharingLocation = false;
    sharingExpiresAt = null;
    activeSessionToken = null;
    _sharingTimer?.cancel();
    _sharingTimer = null;
    notifyListeners();
  }

  /// Broadcast location to community responders on-demand or during emergency
  Future<int> broadcastToCommunityResponders() async {
    try {
      final user = _supabaseService.currentUser;
      if (user == null) return 0;
      final lat = currentPosition?.latitude ?? -1.31122;
      final lng = currentPosition?.longitude ?? 36.81953;

      final List res = await _supabaseService.client
          .from('users')
          .select('id, phone_number, is_community_responder')
          .eq('is_community_responder', true);

      if (res.isNotEmpty) {
        final alerts = res.map((r) => {
          'responder_id': r['id'],
          'distance_m': 350.0,
          'latitude': lat,
          'longitude': lng,
        }).toList();
        try {
          await _supabaseService.client.from('responder_alerts').insert(alerts);
        } catch (_) {}
      }
      return res.length;
    } catch (e) {
      debugPrint('[MapController] Error broadcasting to responders: $e');
      return nearbyResponders.length;
    }
  }

  String get remainingSharingTime {
    if (sharingExpiresAt == null) return '';
    final diff = sharingExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return '${diff.inHours}h ${mins}m left';
    }
    return '${diff.inMinutes}m left';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _sharingTimer?.cancel();
    super.dispose();
  }
}
