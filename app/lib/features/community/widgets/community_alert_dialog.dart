import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/community_alert_model.dart';
import '../controllers/community_alert_controller.dart';

class CommunityAlertDialog extends StatelessWidget {
  final CommunityAlertModel alert;
  final CommunityAlertController controller;

  const CommunityAlertDialog({
    super.key,
    required this.alert,
    required this.controller,
  });

  static Future<void> show(
    BuildContext context,
    CommunityAlertModel alert,
    CommunityAlertController controller,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CommunityAlertDialog(alert: alert, controller: controller),
    );
  }

  void _openGoogleMaps(BuildContext context) async {
    final uri = Uri.parse(alert.mapsLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open external maps application.')),
        );
      }
    }
  }

  void _callPolice(BuildContext context) async {
    final uri = Uri.parse('tel:999');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Siren Header Banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.sosRed, Color(0xFFE11D48)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'COMMUNITY DISTRESS ALERT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.near_me_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'Within 2 km Radius (${alert.formattedDistance})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Body (Minimal Privacy Data)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A community member nearby has activated an emergency distress alert and requires immediate assistance.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Minimal Privacy Info Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          icon: Icons.person_rounded,
                          label: 'Distress User',
                          value: alert.userName,
                        ),
                        const Divider(height: 18, color: Color(0xFFE2E8F0)),
                        _buildInfoRow(
                          icon: Icons.route_rounded,
                          label: 'Estimated Distance',
                          value: alert.formattedDistance,
                          isHighlight: true,
                        ),
                        const Divider(height: 18, color: Color(0xFFE2E8F0)),
                        _buildInfoRow(
                          icon: Icons.location_on_rounded,
                          label: 'GPS Coordinates',
                          value: '${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Map Link Card
                  InkWell(
                    onTap: () => _openGoogleMaps(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Open live alert coordinates in Google Maps',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(Icons.open_in_new_rounded, color: AppColors.primary, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Button 1: Accept & Navigate on In-App Safety Map
                  ElevatedButton.icon(
                    onPressed: () {
                      controller.respondToAlert(alert.panicEventId);
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/map');
                    },
                    icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Accept & Open Safety Map',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Action Button 2: Call Police Hotline
                  OutlinedButton.icon(
                    onPressed: () => _callPolice(context),
                    icon: const Icon(Icons.local_police_rounded, color: AppColors.primary, size: 18),
                    label: const Text(
                      'Dispatch Police (999)',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Action Button 3: Dismiss
                  Center(
                    child: TextButton(
                      onPressed: () {
                        controller.dismissAlert(alert.panicEventId);
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Dismiss / Cannot Respond',
                        style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isHighlight ? AppColors.sosRed : const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? AppColors.sosRed : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
