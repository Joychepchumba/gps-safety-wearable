import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../controllers/map_controller.dart';

enum MapStyleType {
  googleMapsClean,    // Clean Google Maps Vector (lyrs=r) - DEFAULT
  googleMapsHybrid,   // Photorealistic Google Satellite Hybrid (lyrs=y)
  googleMapsRoadmap,  // Classic Google Roadmap (lyrs=m)
  googleMapsTerrain,  // Topographical Contour Relief (lyrs=p)
  mapboxDark,         // Tactical High-Contrast Night (Mapbox Dark)
  openStreetMap,      // OpenStreetMap Community Cartography
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final fmap.MapController _fmapController;
  late final AnimationController _pulseController;
  
  MapStyleType _selectedStyle = MapStyleType.googleMapsClean;
  bool _showPolice = true;
  bool _showContacts = true;
  bool _showResponders = true;
  bool _hasInitiallyCentered = false;
  bool _isFollowingUser = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fmapController = fmap.MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Acquire GPS immediately and automatically center on the user's location
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final mapCtrl = context.read<MapController>();
      mapCtrl.startTracking();

      // 1. If location is already cached, jump camera to user immediately!
      if (mapCtrl.currentPosition != null) {
        _fmapController.move(
          LatLng(mapCtrl.currentPosition!.latitude, mapCtrl.currentPosition!.longitude),
          16.5,
        );
        _hasInitiallyCentered = true;
      }

      // 2. Fetch fresh live GPS fix and smoothly align camera
      await mapCtrl.refreshLocation();
      if (mounted && mapCtrl.currentPosition != null) {
        _fmapController.move(
          LatLng(mapCtrl.currentPosition!.latitude, mapCtrl.currentPosition!.longitude),
          16.5,
        );
        _hasInitiallyCentered = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final mapCtrl = context.read<MapController>();
    if (state == AppLifecycleState.resumed) {
      _hasInitiallyCentered = false;
      mapCtrl.startTracking();
      mapCtrl.refreshLocation().then((_) {
        if (mounted && mapCtrl.currentPosition != null) {
          _fmapController.move(
            LatLng(mapCtrl.currentPosition!.latitude, mapCtrl.currentPosition!.longitude),
            16.5,
          );
          _hasInitiallyCentered = true;
        }
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      mapCtrl.stopTracking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      context.read<MapController>().stopTracking();
    } catch (_) {}
    _fmapController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _recenterOnUser(MapController controller) {
    HapticFeedback.lightImpact();
    setState(() => _isFollowingUser = true);
    final pos = controller.currentPosition;
    if (pos != null) {
      _fmapController.move(
        LatLng(pos.latitude, pos.longitude),
        16.5,
      );
    } else {
      controller.refreshLocation().then((_) {
        if (mounted && controller.currentPosition != null) {
          _fmapController.move(
            LatLng(controller.currentPosition!.latitude, controller.currentPosition!.longitude),
            16.5,
          );
        }
      });
    }
  }

  void _zoomIn() {
    final currentZoom = _fmapController.camera.zoom;
    _fmapController.move(_fmapController.camera.center, (currentZoom + 1).clamp(3.0, 19.5));
  }

  void _zoomOut() {
    final currentZoom = _fmapController.camera.zoom;
    _fmapController.move(_fmapController.camera.center, (currentZoom - 1).clamp(3.0, 19.5));
  }

  String _getTileUrl() {
    switch (_selectedStyle) {
      case MapStyleType.googleMapsClean:
        return 'https://mt1.google.com/vt/lyrs=r&x={x}&y={y}&z={z}';
      case MapStyleType.googleMapsHybrid:
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case MapStyleType.googleMapsRoadmap:
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
      case MapStyleType.googleMapsTerrain:
        return 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case MapStyleType.mapboxDark:
        final token = AppConstants.mapboxToken;
        if (token.isNotEmpty) {
          return 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}@2x?access_token=$token';
        }
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyleType.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }


  void _showLayerSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Map View Style',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                _buildStyleOption(
                  title: 'Google Clean (Vector)',
                  subtitle: 'Modern altered Google vector map with high-contrast streets',
                  type: MapStyleType.googleMapsClean,
                  icon: Icons.map_rounded,
                  badge: 'DEFAULT',
                ),
                _buildStyleOption(
                  title: 'Google Maps Hybrid / Satellite',
                  subtitle: 'Photorealistic satellite imagery with street overlay',
                  type: MapStyleType.googleMapsHybrid,
                  icon: Icons.satellite_alt_rounded,
                ),
                _buildStyleOption(
                  title: 'Tactical Dark (Mapbox)',
                  subtitle: 'Tactical night vision mode for low-light safety',
                  type: MapStyleType.mapboxDark,
                  icon: Icons.nightlight_round,
                  badge: 'NIGHT',
                ),
                _buildStyleOption(
                  title: 'Google Maps Classic',
                  subtitle: 'Standard Google Maps roadmap layout',
                  type: MapStyleType.googleMapsRoadmap,
                  icon: Icons.directions_car_rounded,
                ),
                _buildStyleOption(
                  title: 'Google Maps Terrain',
                  subtitle: 'Topographical relief elevations and contours',
                  type: MapStyleType.googleMapsTerrain,
                  icon: Icons.terrain_rounded,
                ),
                _buildStyleOption(
                  title: 'OpenStreetMap Standard',
                  subtitle: 'Open community cartography fallback',
                  type: MapStyleType.openStreetMap,
                  icon: Icons.public_rounded,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStyleOption({
    required String title,
    required String subtitle,
    required MapStyleType type,
    required IconData icon,
    String? badge,
  }) {
    final isSelected = _selectedStyle == type;
    return InkWell(
      onTap: () {
        setState(() => _selectedStyle = type);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? Colors.white : AppColors.textPrimary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  // --- POLICE STATION SHEET ---
  void _showPoliceStationModal(Map<String, dynamic> station, Position? userPos) {
    double distanceKm = 0.0;
    if (userPos != null) {
      final m = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        station['lat'],
        station['lng'],
      );
      distanceKm = m / 1000.0;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_police_rounded, color: Color(0xFF1E3A8A), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station['name'] ?? 'Police Station',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            station['address'] ?? 'Kenya Police Service',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.near_me_rounded, size: 16, color: Color(0xFF1E3A8A)),
                          const SizedBox(width: 6),
                          Text(
                            distanceKm > 0 ? '${distanceKm.toStringAsFixed(1)} km away' : 'Nearby',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'OPERATIONAL 24/7',
                          style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final phone = station['phone'] as String? ?? '999';
                          final cleanPhone = phone.replaceAll(' ', '').replaceAll('/', ',');
                          final uri = Uri.parse('tel:${cleanPhone.split(',').first}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                        icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                        label: const Text('Call Police', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final lat = station['lat'];
                          final lng = station['lng'];
                          final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.directions_rounded, color: Color(0xFF1E3A8A), size: 18),
                        label: const Text('Directions', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF1E3A8A), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- EMERGENCY CONTACT MODAL ---
  void _showEmergencyContactModal(Map<String, dynamic> contact) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact['name'] ?? 'Emergency Contact',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            contact['phone'] ?? '',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final phone = contact['phone'] as String? ?? '';
                          final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                        icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                        label: const Text('Call Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showLocationSharingDialog(preselectedContact: contact['phone']);
                        },
                        icon: const Icon(Icons.share_location_rounded, color: AppColors.primary, size: 18),
                        label: const Text('Share Live GPS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- LOCATION SHARING SHEET (LINK TO FRIENDS + PICK HOURS FOR CONTACTS + COMMUNITY RESPONDERS) ---
  void _showLocationSharingDialog({String? preselectedContact}) {
    final mapCtrl = context.read<MapController>();
    int selectedHours = 1;
    final Set<String> selectedPhones = {};
    if (preselectedContact != null && preselectedContact.isNotEmpty) {
      selectedPhones.add(preselectedContact);
    } else {
      for (var c in mapCtrl.mappedEmergencyContacts) {
        if (c['phone'] != null) selectedPhones.add(c['phone']);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.share_location_rounded, color: AppColors.primary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Share Live Location',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Real-time GPS with friends & emergency kin',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // OPTION 1: INSTANT LINK TO FRIENDS
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.link_rounded, color: AppColors.accent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Share Tracking Link to Friends',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Send a direct 3D live tracking web link to friends on WhatsApp, SMS, or Telegram.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final link = await mapCtrl.getLiveTrackingLink();
                                      await SharePlus.instance.share(
                                        ShareParams(
                                          text: '📍 Track my live GPS location on SafeGuard:\n$link',
                                          subject: 'My SafeGuard Live Location',
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                                    label: const Text('Share Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final link = await mapCtrl.getLiveTrackingLink();
                                    await Clipboard.setData(ClipboardData(text: link));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Tracking link copied to clipboard!')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textPrimary),
                                  label: const Text('Copy', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.border),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // OPTION 2: EMERGENCY CONTACTS & PICK HOURS
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.timer_outlined, color: AppColors.primary, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Live Location to Contacts (Pick Hours)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Dispatches SMS via Africa\'s Talking with 3D live tracking link for the duration you select.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Select Duration:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [1, 2, 4, 8, 24].map((h) {
                                final isSelected = selectedHours == h;
                                return ChoiceChip(
                                  label: Text(
                                    h == 1 ? '1 Hour' : '$h Hours',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppColors.primary,
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: isSelected ? AppColors.primary : AppColors.border,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    if (val) setModalState(() => selectedHours = h);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Select Contacts to Notify:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            if (mapCtrl.mappedEmergencyContacts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text('No emergency contacts saved yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              )
                            else
                              ...mapCtrl.mappedEmergencyContacts.map((c) {
                                final phone = c['phone'] as String? ?? '';
                                final isChecked = selectedPhones.contains(phone);
                                return CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: AppColors.primary,
                                  title: Text(c['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text(phone, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  value: isChecked,
                                  onChanged: (val) {
                                    setModalState(() {
                                      if (val == true) {
                                        selectedPhones.add(phone);
                                      } else {
                                        selectedPhones.remove(phone);
                                      }
                                    });
                                  },
                                );
                              }),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: selectedPhones.isEmpty
                                    ? null
                                    : () async {
                                        Navigator.pop(ctx);
                                        await mapCtrl.startLocationSharing(
                                          hours: selectedHours,
                                          targetContactPhones: selectedPhones.toList(),
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Sharing live location for $selectedHours hour(s) with ${selectedPhones.length} contact(s) via SMS!'),
                                              backgroundColor: AppColors.primary,
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                                label: Text(
                                  'Start Sharing for $selectedHours Hour${selectedHours > 1 ? "s" : ""}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // OPTION 3: COMMUNITY RESPONDERS
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.health_and_safety_rounded, color: Color(0xFF0F766E), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Community Responders Broadcast',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Community responders are automatically notified whenever emergency mode is activated. You can also share your current location proactively.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final count = await mapCtrl.broadcastToCommunityResponders();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Location shared to $count nearby community responders!'),
                                        backgroundColor: const Color(0xFF0F766E),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.wifi_tethering_rounded, size: 16, color: Color(0xFF0F766E)),
                                label: Text(
                                  'Share to ${mapCtrl.nearbyResponders.length} Community Responders',
                                  style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MapController>();
    final userPos = controller.currentPosition;
    final userLatLng = userPos != null
        ? LatLng(userPos.latitude, userPos.longitude)
        : const LatLng(-1.2921, 36.8219);

    // Automatically align camera the instant user location is locked
    if (userPos != null && (!_hasInitiallyCentered || _isFollowingUser)) {
      if (!_hasInitiallyCentered) {
        _hasInitiallyCentered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _fmapController.move(
              LatLng(userPos.latitude, userPos.longitude),
              16.5,
            );
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Live Safety Map',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Map & Contacts',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () {
              controller.refreshLocation().then((_) {
                if (mounted && controller.currentPosition != null) {
                  _fmapController.move(
                    LatLng(controller.currentPosition!.latitude, controller.currentPosition!.longitude),
                    16.5,
                  );
                }
              });
              controller.loadNearbyResponders();
              controller.loadEmergencyContactsForMap();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. FLUTTER MAP WITH MODERN GOOGLE MAPS STYLES
          fmap.FlutterMap(
            mapController: _fmapController,
            options: fmap.MapOptions(
              initialCenter: userLatLng,
              initialZoom: 16.5,
              minZoom: 3.0,
              maxZoom: 19.5,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isFollowingUser) {
                  setState(() => _isFollowingUser = false);
                }
              },
              interactionOptions: const fmap.InteractionOptions(
                flags: fmap.InteractiveFlag.all,
              ),
            ),
            children: [
              fmap.TileLayer(
                key: ValueKey(_selectedStyle),
                urlTemplate: _getTileUrl(),
                userAgentPackageName: 'com.safeguard.safelink',
                maxZoom: 20,
              ),

              // GPS ACCURACY RADIUS HALO
              if (userPos != null)
                fmap.CircleLayer(
                  circles: [
                    fmap.CircleMarker(
                      point: userLatLng,
                      radius: (userPos.accuracy).clamp(16.0, 70.0),
                      useRadiusInMeter: true,
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderColor: const Color(0xFF2563EB).withValues(alpha: 0.38),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // MARKERS LAYER
              fmap.MarkerLayer(
                markers: [
                  // --- A. USER GPS BEACON ---
                  fmap.Marker(
                    point: userLatLng,
                    width: 76,
                    height: 76,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer radar wave
                            Container(
                              width: 32 + (_pulseController.value * 42),
                              height: 32 + (_pulseController.value * 42),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF2563EB).withValues(
                                  alpha: (1.0 - _pulseController.value) * 0.40,
                                ),
                              ),
                            ),
                            // Inner radar wave
                            Container(
                              width: 24 + (_pulseController.value * 20),
                              height: 24 + (_pulseController.value * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF2563EB).withValues(
                                  alpha: (1.0 - _pulseController.value) * 0.25,
                                ),
                              ),
                            ),
                            // Core Puck
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF2563EB).withValues(alpha: 0.45),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.navigation_rounded, color: Colors.white, size: 12),
                              ),
                            ),
                            // YOU label pill
                            Positioned(
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white, width: 1.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'YOU',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // --- B. POLICE STATIONS ---
                  if (_showPolice)
                    ...controller.policeStations.map((station) {
                      final lat = station['lat'] as double;
                      final lng = station['lng'] as double;
                      return fmap.Marker(
                        point: LatLng(lat, lng),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _showPoliceStationModal(station, userPos),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E3A8A),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.local_police_rounded,
                                size: 22,
                                color: Color(0xFFFBBF24), // Gold badge on navy
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                  // --- C. EMERGENCY CONTACTS ---
                  if (_showContacts)
                    ...controller.mappedEmergencyContacts.map((contact) {
                      final lat = contact['lat'] as double? ?? userLatLng.latitude;
                      final lng = contact['lng'] as double? ?? userLatLng.longitude;
                      return fmap.Marker(
                        point: LatLng(lat, lng),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _showEmergencyContactModal(contact),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE11D48), // Crimson / Rose
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                  // --- D. COMMUNITY RESPONDERS ---
                  if (_showResponders)
                    ...controller.nearbyResponders.map((responder) {
                      final rLat = responder['lat'] as double? ?? userLatLng.latitude;
                      final rLng = responder['lng'] as double? ?? userLatLng.longitude;

                      return fmap.Marker(
                        point: LatLng(rLat, rLng),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Community Responder: ${responder['name']} (approx ${responder['distance']}m away)'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF0F766E), // Emerald
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.health_and_safety_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),

          // 2. GPS STATUS PILL (TOP)
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: InkWell(
              onTap: () {
                if (!controller.isGpsServiceEnabled) {
                  controller.openLocationSettings();
                } else if (!controller.hasLocationPermissionValue) {
                  controller.openAppSettings();
                } else {
                  controller.refreshLocation();
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      controller.isGpsServiceEnabled && controller.hasLocationPermissionValue
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_off_rounded,
                      color: controller.isGpsServiceEnabled && controller.hasLocationPermissionValue
                          ? AppColors.success
                          : AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.locationStatusMessage,
                        style: TextStyle(
                          color: controller.isGpsServiceEnabled && controller.hasLocationPermissionValue
                              ? AppColors.textPrimary
                              : AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!controller.isGpsServiceEnabled || !controller.hasLocationPermissionValue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'FIX',
                          style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 3. MAP FILTER & STYLE QUICK SWITCH PILLS (JUST UNDER STATUS PILL)
          Positioned(
            top: 68,
            left: 16,
            right: 16,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildQuickStyleChip('🗺️ Clean Vector', MapStyleType.googleMapsClean),
                  const SizedBox(width: 6),
                  _buildQuickStyleChip('🛰️ Satellite', MapStyleType.googleMapsHybrid),
                  const SizedBox(width: 6),
                  _buildQuickStyleChip('⚡ Dark Night', MapStyleType.mapboxDark),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: AppColors.border),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Police (${controller.policeStations.length})',
                    icon: Icons.local_police_rounded,
                    color: const Color(0xFF1E3A8A),
                    isActive: _showPolice,
                    onTap: () => setState(() => _showPolice = !_showPolice),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Contacts (${controller.mappedEmergencyContacts.length})',
                    icon: Icons.favorite_rounded,
                    color: const Color(0xFFE11D48),
                    isActive: _showContacts,
                    onTap: () => setState(() => _showContacts = !_showContacts),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Responders (${controller.nearbyResponders.length})',
                    icon: Icons.health_and_safety_rounded,
                    color: const Color(0xFF0F766E),
                    isActive: _showResponders,
                    onTap: () => setState(() => _showResponders = !_showResponders),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _showLayerSelectionModal,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.more_horiz_rounded, size: 14, color: AppColors.textPrimary),
                          SizedBox(width: 4),
                          Text('More Styles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. ACTIVE LOCATION SHARING BANNER (IF ACTIVE)
          if (controller.isSharingLocation)
            Positioned(
              top: 112,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.sosRed,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.sosRed.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sensors_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Live Location Active (${controller.remainingSharingTime})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => controller.stopLocationSharing(),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('STOP', style: TextStyle(color: AppColors.sosRed, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          // 5. MAP FAB CONTROLS (RIGHT SIDE)
          Positioned(
            right: 16,
            bottom: 110,
            child: Column(
              children: [
                _buildMapButton(
                  icon: Icons.layers_rounded,
                  onPressed: _showLayerSelectionModal,
                  tooltip: 'Switch Map View (Google / Mapbox)',
                ),
                const SizedBox(height: 8),
                _buildMapButton(
                  icon: Icons.add,
                  onPressed: _zoomIn,
                  tooltip: 'Zoom In',
                ),
                const SizedBox(height: 8),
                _buildMapButton(
                  icon: Icons.remove,
                  onPressed: _zoomOut,
                  tooltip: 'Zoom Out',
                ),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_isFollowingUser)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 44 + (_pulseController.value * 14),
                            height: 44 + (_pulseController.value * 14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(
                                alpha: (1.0 - _pulseController.value) * 0.5,
                              ),
                            ),
                          );
                        },
                      ),
                    _buildMapButton(
                      icon: Icons.my_location_rounded,
                      color: _isFollowingUser ? AppColors.primary : Colors.white,
                      iconColor: _isFollowingUser ? Colors.white : AppColors.primary,
                      onPressed: () => _recenterOnUser(controller),
                      tooltip: 'Recenter on My Location',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 6. BOTTOM ACTION BAR (SHARE LIVE LOCATION)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -3)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showLocationSharingDialog(),
                        icon: const Icon(Icons.share_location_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'Share Live Location',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStyleChip(String label, MapStyleType type) {
    final isSelected = _selectedStyle == type;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedStyle = type);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A8A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1E3A8A) : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.16 : 0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? color : AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color color = Colors.white,
    Color iconColor = AppColors.textPrimary,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
