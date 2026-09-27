import 'package:flutter/material.dart';
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

          // 2. Top Filter Chips
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: SingleChildScrollView(
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
          ),

          // 3. Danger Zone Live Warning Banner
          if (insideZone != null)
            Positioned(
              top: 66,
              left: 16,
              right: 16,
              child: Container(
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
            ),

          // 3b. Active Community Distress Emergency Banner (Within 2 km)
          if (communityCtrl.activeAlerts.isNotEmpty)
            Positioned(
              top: insideZone != null ? 140 : 66,
              left: 16,
              right: 16,
              child: GestureDetector(
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
                            onPressed: () => controller.shareLiveLocation(),
                            icon: const Icon(Icons.share_location_rounded, color: AppColors.primary, size: 18),
                            label: const Text(
                              'Share Live GPS',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.primary, width: 1.5),
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
}
