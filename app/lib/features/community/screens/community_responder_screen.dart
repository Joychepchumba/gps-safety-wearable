import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/controllers/auth_controller.dart';

class DistressUserEntry {
  final String id;
  final String victimName;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String triggerType; // 'phone_button', 'pendant_touch', 'voice', 'ble_beacon'
  final String sourceChannel; // 'BLE Bluetooth' or 'Cloud + GPS'
  final int? rssi;
  final DateTime detectedAt;
  String status; // 'active', 'accepted'

  DistressUserEntry({
    required this.id,
    required this.victimName,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.triggerType,
    required this.sourceChannel,
    this.rssi,
    required this.detectedAt,
    this.status = 'active',
  });
}

class CommunityResponderScreen extends StatefulWidget {
  const CommunityResponderScreen({super.key});

  @override
  State<CommunityResponderScreen> createState() => _CommunityResponderScreenState();
}

class _CommunityResponderScreenState extends State<CommunityResponderScreen> {
  final BleService _bleService = sl<BleService>();
  final LocationService _locationService = sl<LocationService>();
  final SupabaseService _supabaseService = sl<SupabaseService>();
  final NotificationService _notificationService = sl<NotificationService>();
  final MapController _mapController = MapController();

  LatLng _myLocation = const LatLng(-1.2907850038543573, 36.78176897301627); // Alina Harbour Apartments default
  bool _hasLocationFix = false;
  bool _isScanningBle = false;
  bool _isLoadingCloud = false;
  String _responderStatus = 'available'; // 'available', 'responding', 'offline'

  final Map<String, DistressUserEntry> _distressUsers = {};
  List<Map<String, dynamic>> _communityResponders = [];
  StreamSubscription<List<BleDistressBeacon>>? _bleDistressSub;
  StreamSubscription<Position>? _positionSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initResponderDashboard();
  }

  Future<void> _initResponderDashboard() async {
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user != null) {
      _responderStatus = user.isCommunityResponder ? (user.responderStatus ?? 'available') : 'offline';
    }

    // Seed any already-detected BLE beacons immediately on screen open
    if (_bleService.activeBeacons.isNotEmpty) {
      _ingestBleBeacons(_bleService.activeBeacons, silent: true);
    }

    await _refreshMyLocation();
    _startLiveLocationStream();
    await _startBleDistressRadar();
    await _fetchCloudDistressAndResponders();

    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) {
        _fetchCloudDistressAndResponders();
        if (!_bleService.isScanning) {
          _bleService.startScan(
            timeout: const Duration(seconds: 20),
            forCommunityResponderRadar: true,
          );
        }
      }
    });
  }

  void _startLiveLocationStream() {
    _positionSub?.cancel();
    try {
      _positionSub = _locationService.getPositionStream().listen((pos) {
        if (!mounted) return;
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _hasLocationFix = true;
          // Recalculate live distances to all active distress users
          for (final key in _distressUsers.keys.toList()) {
            final d = _distressUsers[key]!;
            final newDist = Geolocator.distanceBetween(
              _myLocation.latitude,
              _myLocation.longitude,
              d.latitude,
              d.longitude,
            );
            _distressUsers[key] = DistressUserEntry(
              id: d.id,
              victimName: d.victimName,
              latitude: d.latitude,
              longitude: d.longitude,
              distanceMeters: newDist,
              triggerType: d.triggerType,
              sourceChannel: d.sourceChannel,
              rssi: d.rssi,
              detectedAt: d.detectedAt,
              status: d.status,
            );
          }
        });
      });
    } catch (_) {}
  }

  Future<void> _refreshMyLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
      if (pos != null && mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _hasLocationFix = true;
        });
        try {
          _mapController.move(_myLocation, 15.5);
        } catch (_) {}

        final user = context.read<AuthController>().currentUser;
        if (user != null) {
          await _supabaseService.updateUserProfile(
            userId: user.id,
            lastLat: pos.latitude,
            lastLng: pos.longitude,
          );
        }
      }
    } catch (_) {}
  }

  void _ingestBleBeacons(List<BleDistressBeacon> beacons, {bool silent = false}) {
    if (!mounted) return;
    bool addedNew = false;
    for (final b in beacons) {
      final hasValidCoords = b.latitude.abs() > 0.0001 || b.longitude.abs() > 0.0001;
      final lat = hasValidCoords ? b.latitude : _myLocation.latitude;
      final lng = hasValidCoords ? b.longitude : _myLocation.longitude;
      final dist = hasValidCoords
          ? Geolocator.distanceBetween(
              _myLocation.latitude,
              _myLocation.longitude,
              lat,
              lng,
            )
          : b.estimatedDistanceMeters;

      final key = 'BLE-${b.userTagHex}';
      final existing = _distressUsers[key];
      if (existing == null) {
        addedNew = true;
      }
      final isPendant = b.sourceType == 'pendant_ble';
      _distressUsers[key] = DistressUserEntry(
        id: key,
        victimName: b.resolvedUserName ??
            existing?.victimName ??
            (isPendant
                ? 'SafeGuard Pendant (${b.userTagHex.toUpperCase()})'
                : 'Nearby SafeLink User (${b.userTagHex.toUpperCase()})'),
        latitude: lat,
        longitude: lng,
        distanceMeters: dist,
        triggerType: isPendant ? 'pendant_touch' : 'phone_button',
        sourceChannel: 'BLE Bluetooth (${b.rssi} dBm)',
        rssi: b.rssi,
        detectedAt: b.detectedAt,
        status: existing?.status ?? 'active',
      );
    }
    setState(() {});
    if (!silent && addedNew && beacons.isNotEmpty) {
      final first = beacons.first;
      final isPendant = first.sourceType == 'pendant_ble';
      _notificationService.showCommunityDistressPopup(
        victimName: first.resolvedUserName ??
            (isPendant
                ? 'SafeGuard Pendant (${first.userTagHex.toUpperCase()})'
                : 'Nearby SafeLink User (${first.userTagHex.toUpperCase()})'),
        sourceLabel: isPendant ? 'Pendant SOS via BLE Bluetooth' : 'Phone SOS via BLE Bluetooth',
        distanceMeters: first.estimatedDistanceMeters,
      );
    }
  }

  Future<void> _startBleDistressRadar() async {
    setState(() => _isScanningBle = true);
    _bleDistressSub?.cancel();
    _bleDistressSub = _bleService.distressBeaconsStream.listen((beacons) {
      _ingestBleBeacons(beacons);
    });

    await _bleService.startScan(
      timeout: const Duration(seconds: 20),
      forCommunityResponderRadar: true,
    );
  }

  Future<void> _fetchCloudDistressAndResponders() async {
    if (!mounted) return;
    setState(() => _isLoadingCloud = true);
    try {
      final myUserId = context.read<AuthController>().currentUser?.id;

      // 1. Fetch active panic events from Supabase (both phone & pendant panic events)
      final activeEvents = await _supabaseService.client
          .from('panic_events')
          .select('id, user_id, latitude, longitude, trigger_type, status, timestamp')
          .eq('status', 'active')
          .order('timestamp', ascending: false)
          .limit(15);

      for (final row in (activeEvents as List)) {
        final eventId = row['id'].toString();
        final victimId = row['user_id']?.toString() ?? '';
        final lat = (row['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (row['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat == 0.0 && lng == 0.0) continue;

        final dist = Geolocator.distanceBetween(
          _myLocation.latitude,
          _myLocation.longitude,
          lat,
          lng,
        );
        // Include distress events within 5 km
        if (dist <= 5000) {
          String victimLabel = victimId == myUserId
              ? 'You (Active SOS Broadcast)'
              : 'SafeLink User #${victimId.length >= 6 ? victimId.substring(0, 6).toUpperCase() : victimId}';
          try {
            final uRow = await _supabaseService.client
                .from('users')
                .select('full_name')
                .eq('id', victimId)
                .maybeSingle();
            if (uRow != null && uRow['full_name'] != null && uRow['full_name'].toString().isNotEmpty) {
              victimLabel = uRow['full_name'].toString();
            }
          } catch (_) {}

          _distressUsers['CLOUD-$eventId'] = DistressUserEntry(
            id: eventId,
            victimName: victimLabel,
            latitude: lat,
            longitude: lng,
            distanceMeters: dist,
            triggerType: row['trigger_type']?.toString() ?? 'phone_button',
            sourceChannel: 'Cloud + BLE Mesh',
            detectedAt: DateTime.tryParse(row['timestamp']?.toString() ?? '') ?? DateTime.now(),
          );
        }
      }

      // 2. Fetch registered Community Responders
      final respondersData = await _supabaseService.client
          .from('users')
          .select('id, full_name, responder_status, is_community_responder, last_lat, last_lng')
          .eq('is_community_responder', true)
          .limit(25);

      if (mounted) {
        setState(() {
          _communityResponders = List<Map<String, dynamic>>.from(respondersData as List);
        });
      }
    } catch (_) {
      // Ignore network/table errors gracefully
    } finally {
      if (mounted) {
        setState(() => _isLoadingCloud = false);
      }
    }
  }

  Future<void> _toggleCommunityResponderOptIn(bool enabled) async {
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    final newStatus = enabled ? 'available' : 'offline';
    setState(() => _responderStatus = newStatus);
    if (user != null) {
      await auth.updateProfile(
        fullName: user.fullName,
        phoneNumber: user.phoneNumber,
        isCommunityResponder: enabled,
      );
      await _supabaseService.updateUserProfile(
        userId: user.id,
        isCommunityResponder: enabled,
        responderStatus: newStatus,
      );
    }
    await _fetchCloudDistressAndResponders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'You are now a Verified Community Responder! Nearby SOS alerts via BLE & Cloud are active.'
                : 'Opted out of Community Responder alerts.',
          ),
          backgroundColor: enabled ? AppColors.success : Colors.grey.shade800,
        ),
      );
    }
  }

  Future<void> _setResponderAvailability(String status) async {
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    setState(() => _responderStatus = status);
    if (user != null) {
      await auth.updateProfile(
        fullName: user.fullName,
        phoneNumber: user.phoneNumber,
        isCommunityResponder: status != 'offline',
      );
      await _supabaseService.updateUserProfile(
        userId: user.id,
        isCommunityResponder: status != 'offline',
        responderStatus: status,
      );
    }
    await _fetchCloudDistressAndResponders();
  }

  void _simulateNearbyBleDistress({required bool fromPendant}) {
    final simLat = _myLocation.latitude + (fromPendant ? 0.00065 : -0.00055);
    final simLng = _myLocation.longitude + (fromPendant ? 0.00050 : 0.00060);
    final dist = Geolocator.distanceBetween(
      _myLocation.latitude,
      _myLocation.longitude,
      simLat,
      simLng,
    );
    final key = fromPendant ? 'SIM-BLE-PENDANT' : 'SIM-BLE-PHONE';
    final entry = DistressUserEntry(
      id: key,
      victimName: fromPendant ? 'SafeLink Pendant #JK001 (BLE SOS)' : 'Nearby App User (Phone SOS)',
      latitude: simLat,
      longitude: simLng,
      distanceMeters: dist,
      triggerType: fromPendant ? 'pendant_touch' : 'phone_button',
      sourceChannel: 'BLE Bluetooth (-58 dBm)',
      rssi: -58,
      detectedAt: DateTime.now(),
    );

    setState(() {
      _distressUsers[key] = entry;
    });

    try {
      _mapController.move(LatLng(simLat, simLng), 16.2);
    } catch (_) {}

    _notificationService.showCommunityDistressPopup(
      victimName: entry.victimName,
      sourceLabel: fromPendant ? 'Pendant SOS (BLE)' : 'Phone Panic (BLE)',
      distanceMeters: dist,
    );
  }

  Future<void> _respondToDistress(DistressUserEntry entry) async {
    setState(() {
      entry.status = 'accepted';
      _responderStatus = 'responding';
    });
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user != null) {
      await _supabaseService.updateUserProfile(
        userId: user.id,
        isCommunityResponder: true,
        responderStatus: 'responding',
      );
    }
    try {
      _mapController.move(LatLng(entry.latitude, entry.longitude), 16.5);
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Responding to ${entry.victimName}! Live route pinned on map.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _openExternalDirections(DistressUserEntry entry) async {
    // Always resolve the latest live coordinates from _distressUsers
    final liveEntry = _distressUsers[entry.id] ?? entry;
    final destLat = liveEntry.latitude;
    final destLng = liveEntry.longitude;

    // Center the in-app radar map on the active route first
    try {
      _mapController.move(LatLng(destLat, destLng), 16.5);
    } catch (_) {}

    final googleMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=${_myLocation.latitude},${_myLocation.longitude}&destination=$destLat,$destLng&travelmode=walking',
    );
    final geoFallbackUri = Uri.parse(
      'geo:$destLat,$destLng?q=$destLat,$destLng(${Uri.encodeComponent(liveEntry.victimName)})',
    );

    try {
      final launched = await launchUrl(
        googleMapsUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(geoFallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(geoFallbackUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _bleDistressSub?.cancel();
    _positionSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final auth = context.watch<AuthController>();
    final user = auth.currentUser;
    final isOptedIn = user?.isCommunityResponder ?? false;
    final distressList = _distressUsers.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: AppColors.success, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Community Responders',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: themeController.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              themeController.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: themeController.isDarkMode ? Colors.amber : AppColors.accent,
              size: 20,
            ),
            onPressed: () => themeController.toggleDarkMode(),
          ),
          IconButton(
            tooltip: 'Rescan BLE & Cloud',
            icon: Icon(
              _isScanningBle ? Icons.bluetooth_connected_rounded : Icons.refresh_rounded,
              color: AppColors.accent,
              size: 20,
            ),
            onPressed: () {
              _refreshMyLocation();
              _startBleDistressRadar();
              _fetchCloudDistressAndResponders();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. RESPONDER IDENTITY & OPT-IN CARD
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOptedIn
                        ? AppColors.success.withValues(alpha: 0.5)
                        : context.cardBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: isOptedIn
                                ? AppColors.success.withValues(alpha: 0.15)
                                : context.inputBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isOptedIn ? Icons.verified_user_rounded : Icons.shield_outlined,
                            color: isOptedIn ? AppColors.success : context.textSecondary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      isOptedIn
                                          ? 'Verified Community Responder'
                                          : 'Community Responder Network',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (isOptedIn) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isOptedIn
                                    ? 'Scanning BLE Bluetooth & Cloud for nearby Phone or Pendant SOS alerts.'
                                    : 'Opt in to receive nearby BLE Bluetooth & GPS distress alerts and help others.',
                                style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isOptedIn,
                          activeThumbColor: AppColors.success,
                          onChanged: _toggleCommunityResponderOptIn,
                        ),
                      ],
                    ),
                    if (isOptedIn) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildStatusChip(context, 'available', 'Available', AppColors.success),
                          const SizedBox(width: 8),
                          _buildStatusChip(context, 'responding', 'Responding', Colors.orangeAccent),
                          const SizedBox(width: 8),
                          _buildStatusChip(context, 'offline', 'Standby', Colors.grey),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 2. LIVE RESPONDER RADAR MAP (Shows My Location + Users in Distress)
              Container(
                height: 235,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: distressList.isNotEmpty
                        ? AppColors.sosRed.withValues(alpha: 0.7)
                        : context.cardBorder,
                    width: distressList.isNotEmpty ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _myLocation,
                          initialZoom: 15.2,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safelink.safelink_app',
                          ),
                          // BLE Radar Range Circle around Responder
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: _myLocation,
                                radius: 120,
                                useRadiusInMeter: true,
                                color: AppColors.accent.withValues(alpha: 0.10),
                                borderColor: AppColors.accent.withValues(alpha: 0.45),
                                borderStrokeWidth: 1.5,
                              ),
                            ],
                          ),
                          // Live Navigation Route Line from Responder to Distress User(s)
                          if (distressList.isNotEmpty)
                            PolylineLayer(
                              polylines: distressList.map((d) {
                                final isAccepted = d.status == 'accepted';
                                return Polyline(
                                  points: [
                                    _myLocation,
                                    LatLng(d.latitude, d.longitude),
                                  ],
                                  strokeWidth: isAccepted ? 4.5 : 3.0,
                                  color: isAccepted
                                      ? AppColors.success
                                      : AppColors.sosRed.withValues(alpha: 0.85),
                                );
                              }).toList(),
                            ),
                          MarkerLayer(
                            markers: [
                              // Responder's Own Location Marker
                              Marker(
                                point: _myLocation,
                                width: 110,
                                height: 70,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'YOU (Responder)',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: const Icon(
                                        Icons.shield_rounded,
                                        color: Colors.black,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Nearby Users in Distress Markers
                              ...distressList.map(
                                (d) => Marker(
                                  point: LatLng(d.latitude, d.longitude),
                                  width: 140,
                                  height: 76,
                                  child: GestureDetector(
                                    onTap: () => _respondToDistress(d),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.sosRed,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'SOS • ${d.distanceMeters.round()}m',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: AppColors.sosRed,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.sosRed.withValues(alpha: 0.6),
                                                blurRadius: 12,
                                                spreadRadius: 3,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            d.triggerType.contains('pendant')
                                                ? Icons.watch_rounded
                                                : Icons.sos_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Top overlay badge showing BLE radar status + coordinates
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: context.cardBg.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: context.cardBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      color: AppColors.accent,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'BLE Radar • ${_myLocation.latitude.toStringAsFixed(4)}, ${_myLocation.longitude.toStringAsFixed(4)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'center_me_btn',
                              backgroundColor: context.cardBg.withValues(alpha: 0.92),
                              onPressed: _refreshMyLocation,
                              child: const Icon(Icons.my_location_rounded, color: AppColors.success, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 3. USERS IN DISTRESS SECTION (BLE + Cloud)
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.sosRed, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Users in Distress Nearby (${distressList.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'pendant') {
                        _simulateNearbyBleDistress(fromPendant: true);
                      } else {
                        _simulateNearbyBleDistress(fromPendant: false);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'pendant',
                        child: Text('Simulate Nearby Pendant BLE SOS'),
                      ),
                      PopupMenuItem(
                        value: 'phone',
                        child: Text('Simulate Nearby Phone BLE SOS'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radar_rounded, size: 13, color: AppColors.accent),
                          SizedBox(width: 4),
                          Text(
                            'Test BLE Alert',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (distressList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 36),
                      const SizedBox(height: 6),
                      Text(
                        'No Users in Distress Detected Nearby',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Listening continuously for BLE Bluetooth SOS beacons (Phone & SafeGuard Pendant) and Cloud GPS panic broadcasts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                )
              else
                ...distressList.map((entry) => _buildDistressCard(context, entry)),

              const SizedBox(height: 18),

              // 4. WHO IS A COMMUNITY RESPONDER? (Active Responders Directory)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Active Community Responders (${_communityResponders.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  if (_isLoadingCloud)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_communityResponders.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.cardBorder),
                  ),
                  child: Text(
                    'Opt in above to appear as a verified Community Responder in your area.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                )
              else
                ..._communityResponders.map((resp) {
                  final name = resp['full_name']?.toString().isNotEmpty == true
                      ? resp['full_name'].toString()
                      : 'SafeLink Responder';
                  final status = resp['responder_status']?.toString() ?? 'available';
                  final rLat = (resp['last_lat'] as num?)?.toDouble();
                  final rLng = (resp['last_lng'] as num?)?.toDouble();
                  double? distMeters;
                  if (rLat != null && rLng != null && _hasLocationFix) {
                    distMeters = Geolocator.distanceBetween(
                      _myLocation.latitude,
                      _myLocation.longitude,
                      rLat,
                      rLng,
                    );
                  }
                  final isMe = resp['id'] == user?.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.cardBorder),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.success.withValues(alpha: 0.18),
                          child: const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      isMe ? '$name (You)' : name,
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified_rounded, color: AppColors.accent, size: 15),
                                ],
                              ),
                              Text(
                                distMeters != null
                                    ? '${(distMeters / 1000).toStringAsFixed(2)} km away • Verified Responder'
                                    : 'Verified SafeLink Community Responder',
                                style: TextStyle(color: context.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'responding'
                                ? Colors.orange.withValues(alpha: 0.2)
                                : AppColors.success.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: status == 'responding' ? Colors.orangeAccent : AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String value, String label, Color color) {
    final selected = _responderStatus == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setResponderAvailability(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.22) : context.inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : context.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? color : context.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistressCard(BuildContext context, DistressUserEntry entry) {
    final isPendant = entry.triggerType.contains('pendant');
    final isVoice = entry.triggerType.contains('voice');
    final triggerBadge = isPendant
        ? 'Pendant SOS'
        : (isVoice ? 'Voice Keyword SOS' : 'Phone Panic SOS');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sosRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.sosRed,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPendant ? Icons.watch_rounded : Icons.sos_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.victimName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$triggerBadge • ${entry.sourceChannel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.sosRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entry.distanceMeters < 1000
                      ? '${entry.distanceMeters.round()} m'
                      : '${(entry.distanceMeters / 1000).toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'GPS Location: ${entry.latitude.toStringAsFixed(5)}, ${entry.longitude.toStringAsFixed(5)}',
            style: TextStyle(color: context.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _respondToDistress(entry),
                  icon: Icon(
                    entry.status == 'accepted' ? Icons.check_circle : Icons.volunteer_activism_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                  label: Text(
                    entry.status == 'accepted' ? 'Responding Now' : 'Accept & Respond',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: entry.status == 'accepted' ? AppColors.success : AppColors.sosRed,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openExternalDirections(entry),
                icon: const Icon(Icons.directions_walk_rounded, size: 15, color: AppColors.accent),
                label: const Text(
                  'Navigate',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
