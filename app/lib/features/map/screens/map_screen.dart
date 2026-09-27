import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' hide MapController;
import 'package:flutter_map/flutter_map.dart' as fmap show MapController;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/map_controller.dart';
import '../models/police_station_model.dart';
import '../models/danger_zone_model.dart';
import '../../community/controllers/community_alert_controller.dart';
import '../../community/widgets/community_alert_dialog.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final fmap.MapController _mapUiController = fmap.MapController();
  String _activeFilter = 'all'; // 'all', 'police', 'danger', 'responders'
  bool _showBottomDetails = true;
  bool _hasCenteredOnUser = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapController>().checkActiveSharingSession();
    });
  }

  void _recenterMap(double lat, double lng, {double zoom = 16.5}) {
    _mapUiController.move(LatLng(lat, lng), zoom);
  }

  void _callPolice(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot launch phone dialer for $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MapController>();
    final communityCtrl = context.watch<CommunityAlertController>();
    final userPos = controller.currentPosition;
    final userLatLng = userPos != null
        ? LatLng(userPos.latitude, userPos.longitude)
        : const LatLng(-1.2825, 36.8222);

    // Auto-focus and zoom to user's location when GPS is available
    if (userPos != null && !_hasCenteredOnUser) {
      _hasCenteredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _recenterMap(userPos.latitude, userPos.longitude, zoom: 16.5);
        }
      });
    }

    final nearestPolice = controller.nearestPoliceStation;
    final insideZone = controller.activeDangerZoneWarning;

    // Filter markers
    final showPolice = _activeFilter == 'all' || _activeFilter == 'police';
    final showDanger = _activeFilter == 'all' || _activeFilter == 'danger';
    final showResponders = _activeFilter == 'all' || _activeFilter == 'responders';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Live Safety Map',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => controller.initialize(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Interactive Flutter Map
          FlutterMap(
            mapController: _mapUiController,
            options: MapOptions(
              initialCenter: userLatLng,
              initialZoom: 16.5,
              minZoom: 4.0,
              maxZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.safelink.gps_safety_wearable',
              ),

              // Danger Zone Geofence Circle Overlays
              CircleLayer(
                circles: [
                  if (showDanger)
                    ...controller.dangerZones.map((zone) {
                      final isInside = zone.id == insideZone?.id;
                      return CircleMarker(
                        point: LatLng(zone.latitude, zone.longitude),
                        color: isInside
                            ? AppColors.sosRed.withValues(alpha: 0.35)
                            : AppColors.warning.withValues(alpha: 0.22),
                        borderColor: isInside ? AppColors.sosRed : AppColors.warning,
                        borderStrokeWidth: isInside ? 2.5 : 1.5,
                        useRadiusInMeter: true,
                        radius: zone.radiusMeters,
                      );
                    }),

                  // Active Community Distress Emergency Beacons (Within 2 km)
                  ...communityCtrl.activeAlerts.map((alert) {
                    return CircleMarker(
                      point: LatLng(alert.latitude, alert.longitude),
                      color: AppColors.sosRed.withValues(alpha: 0.28),
                      borderColor: AppColors.sosRed,
                      borderStrokeWidth: 2.5,
                      useRadiusInMeter: true,
                      radius: 120.0,
                    );
                  }),
                ],
              ),

              // Markers Layer
              MarkerLayer(
                markers: [
                  // Active Community Distress Pins (Within 2 km)
                  ...communityCtrl.activeAlerts.map((alert) {
                    return Marker(
                      point: LatLng(alert.latitude, alert.longitude),
                      width: 54,
                      height: 54,
                      child: GestureDetector(
                        onTap: () => CommunityAlertDialog.show(context, alert, communityCtrl),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.sosRed,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    );
                  }),

                  // User GPS location marker
                  Marker(
                    point: userLatLng,
                    width: 50,
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  ),

                  // Police Stations Markers
                  if (showPolice)
                    ...controller.policeStations.take(15).map((station) {
                      return Marker(
                        point: LatLng(station.latitude, station.longitude),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _showStationModal(context, station, userPos?.latitude, userPos?.longitude),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.local_police_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      );
                    }),

                  // Danger Zones Center Markers
                  if (showDanger)
                    ...controller.dangerZones.map((zone) {
                      return Marker(
                        point: LatLng(zone.latitude, zone.longitude),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showDangerZoneModal(context, zone, userPos?.latitude, userPos?.longitude),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.sosRed,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      );
                    }),

                  // Community Responders Markers
                  if (showResponders)
                    ...controller.nearbyResponders.map((resp) {
                      return Marker(
                        point: LatLng(resp['lat'], resp['lng']),
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 16),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),

          // 2. Top Interactive Banners & Filter Chips
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2a. Active Live 3D Location Sharing Banner
                if (controller.isSharingLocation) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6), width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10B981),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.8),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LIVE 3D SHARING ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${controller.remainingSharingTimeFormatted} remaining • Real-time GPS beacon',
                                style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                          tooltip: 'Share Live Link',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => controller.shareViaNativeSheet(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                          tooltip: 'Copy Tracking Link',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            if (controller.shareableLink != null) {
                              Clipboard.setData(ClipboardData(text: controller.shareableLink!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('3D Tracking link copied to clipboard!'),
                                  backgroundColor: Color(0xFF10B981),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 20),
                          tooltip: 'Cancel Sharing',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            await controller.cancelRealTimeLocationSharing();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Real-time location sharing stopped.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // 2b. Danger Zone Live Warning Banner
                if (insideZone != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.sosRed,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'HAZARD WARNING: HIGH-RISK ZONE',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'You entered ${insideZone.locationName}. Stay vigilant and keep wearable ready.',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // 2c. Active Community Distress Emergency Banner (Within 2 km)
                if (communityCtrl.activeAlerts.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => CommunityAlertDialog.show(
                      context,
                      communityCtrl.activeAlerts.first,
                      communityCtrl,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.sosRed,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🚨 DISTRESS NEARBY: ${communityCtrl.activeAlerts.first.userName.toUpperCase()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${communityCtrl.activeAlerts.first.formattedDistance} • Tap to view location & navigate',
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // 2d. Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All Safety Points', Icons.layers_outlined),
                      const SizedBox(width: 8),
                      _buildFilterChip('police', 'Police Stations', Icons.local_police_outlined),
                      const SizedBox(width: 8),
                      _buildFilterChip('danger', 'Crime Hotspots', Icons.warning_amber_rounded),
                      const SizedBox(width: 8),
                      _buildFilterChip('responders', 'Nearby Responders', Icons.health_and_safety_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Map Control Buttons (Recenter & Voice Wake Word)
          Positioned(
            right: 16,
            bottom: _showBottomDetails ? 240 : 80,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_btn',
                  backgroundColor: Colors.white,
                  onPressed: () => _recenterMap(userLatLng.latitude, userLatLng.longitude),
                  child: const Icon(Icons.my_location_rounded, color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'voice_btn',
                  backgroundColor: Colors.white,
                  onPressed: () => Navigator.pushNamed(context, '/voice-activation'),
                  child: const Icon(Icons.record_voice_over_rounded, color: AppColors.accent),
                ),
              ],
            ),
          ),

          // 5. Bottom Safety Drawer Card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() => _showBottomDetails = !_showBottomDetails),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_showBottomDetails) ...[
                    // Nearest Police Station Card
                    if (nearestPolice != null && userPos != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_police_rounded, color: AppColors.secondary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nearestPolice.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${nearestPolice.formattedDistance(userPos.latitude, userPos.longitude)} • 24/7 Response',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _callPolice(nearestPolice.phoneNumber),
                              icon: const Icon(Icons.call, size: 14, color: Colors.white),
                              label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.secondary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Share Live Track & SOS Emergency Action Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showShareLocationSheet(context, controller),
                            icon: Icon(
                              controller.isSharingLocation ? Icons.wifi_tethering_rounded : Icons.share_location_rounded,
                              color: controller.isSharingLocation ? const Color(0xFF10B981) : AppColors.primary,
                              size: 18,
                            ),
                            label: Text(
                              controller.isSharingLocation
                                  ? 'Sharing (${controller.remainingSharingTimeFormatted})'
                                  : 'Share Live 3D',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: controller.isSharingLocation ? const Color(0xFF10B981) : AppColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                color: controller.isSharingLocation ? const Color(0xFF10B981) : AppColors.primary,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pushNamed(context, '/emergency'),
                            icon: const Icon(Icons.crisis_alert_rounded, color: Colors.white, size: 18),
                            label: const Text(
                              'Trigger SOS',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sosRed,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon) {
    final isSelected = _activeFilter == key;
    return InkWell(
      onTap: () => setState(() => _activeFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStationModal(BuildContext context, PoliceStationModel station, double? userLat, double? userLng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.secondary,
                  child: Icon(Icons.local_police, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (userLat != null && userLng != null)
                        Text(station.formattedDistance(userLat, userLng), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _callPolice(station.phoneNumber);
              },
              icon: const Icon(Icons.phone, color: Colors.white),
              label: Text('Call ${station.phoneNumber}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDangerZoneModal(BuildContext context, DangerZoneModel zone, double? userLat, double? userLng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.sosRed,
                  child: Icon(Icons.warning_amber_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.locationName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${zone.radiusMeters.toStringAsFixed(0)}m risk radius', style: const TextStyle(color: AppColors.sosRed, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(zone.description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/emergency');
              },
              icon: const Icon(Icons.crisis_alert_rounded, color: Colors.white),
              label: const Text('Trigger Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sosRed,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareLocationSheet(BuildContext context, MapController controller) {
    int selectedHours = controller.sharingDurationHours.clamp(1, 24);
    if (selectedHours < 1 || selectedHours > 24) selectedHours = 8;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isSharing = controller.isSharingLocation;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSharing
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSharing ? Icons.wifi_tethering_rounded : Icons.share_location_rounded,
                        color: isSharing ? const Color(0xFF10B981) : AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSharing ? 'Live 3D Sharing Active' : 'Share Live 3D Location',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            isSharing
                                ? '${controller.remainingSharingTimeFormatted} left • Real-time GPS beacon'
                                : 'Select duration (1h to 24h) for your live Mapbox 3D tracking link',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSharing ? const Color(0xFF059669) : AppColors.textSecondary,
                              fontWeight: isSharing ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // If already sharing, display the active URL and controls
                if (isSharing && controller.shareableLink != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR 3D MAPBOX TRACKING LINK',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.shareableLink!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: controller.shareableLink!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tracking link copied to clipboard!'),
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      controller.shareViaNativeSheet();
                    },
                    icon: const Icon(Icons.share_rounded, color: Colors.white),
                    label: const Text('Share Link via WhatsApp / SMS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await controller.cancelRealTimeLocationSharing();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Live location sharing cancelled.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.cancel_outlined, color: AppColors.sosRed),
                    label: const Text('Stop Location Sharing', style: TextStyle(color: AppColors.sosRed, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.sosRed),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ] else ...[
                  // Not sharing yet: Duration Picker
                  const Text(
                    'SHARING DURATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Quick Duration Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 4, 8, 12, 24].map((hours) {
                      final isSel = selectedHours == hours;
                      final label = hours == 8 ? '8h (Default)' : hours == 24 ? '24h (Max)' : '${hours}h';
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSel,
                        selectedColor: AppColors.primary,
                        backgroundColor: Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : AppColors.textPrimary,
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setSheetState(() => selectedHours = hours);
                          }
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),

                  // Slider for continuous 1 to 24 hours selection
                  Row(
                    children: [
                      const Text('1h', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: selectedHours.toDouble(),
                          min: 1.0,
                          max: 24.0,
                          divisions: 23,
                          activeColor: AppColors.primary,
                          label: '${selectedHours}h',
                          onChanged: (val) {
                            setSheetState(() => selectedHours = val.round());
                          },
                        ),
                      ),
                      const Text('24h', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                    ],
                  ),

                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your phone will ping GPS every 10 seconds. Live 3D Mapbox tracking link expires in $selectedHours hour${selectedHours > 1 ? 's' : ''}. You can cancel anytime.',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Start Sharing Button
                  ElevatedButton.icon(
                    onPressed: controller.isStartingSharing
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            final link = await controller.startRealTimeLocationSharing(
                              durationHours: selectedHours,
                            );
                            if (context.mounted && link != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Live 3D tracking started for ${selectedHours}h!'),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                              // Prompt native share immediately
                              controller.shareViaNativeSheet();
                            }
                          },
                    icon: controller.isStartingSharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.share_location_rounded, color: Colors.white),
                    label: Text(
                      controller.isStartingSharing
                          ? 'Starting Live Beacon...'
                          : 'Start Live 3D Sharing (${selectedHours}h)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
