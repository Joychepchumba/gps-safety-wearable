import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../controllers/alert_controller.dart';
import '../../../models/panic_event_model.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  String _selectedFilter = 'all'; // 'all', 'active', 'resolved', 'false_alarm'

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlertController>();

    final filteredAlerts = controller.alerts.where((a) {
      if (_selectedFilter == 'all') return true;
      return a.status.toLowerCase() == _selectedFilter;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Alert History & Telemetry',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh History',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => controller.refreshAlerts(),
          ),
        ],
      ),
      body: controller.isLoading && controller.alerts.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: controller.refreshAlerts,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- 1. TOP ANALYTICS DASHBOARD (RESPONSIVE & OVERFLOW-SAFE) ---
                    _buildAnalyticsDashboard(controller),
                    const SizedBox(height: 14),

                    // --- 2. FILTER TABS ---
                    _buildFilterTabs(controller),
                    const SizedBox(height: 14),

                    // --- 3. ALERTS LIST ---
                    if (filteredAlerts.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.shield_outlined, size: 30, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedFilter == 'all'
                                  ? 'No alerts recorded yet'
                                  : 'No $_selectedFilter alerts found',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'When an SOS is triggered, complete location telemetry & resolution logs will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (context, index) {
                          return _buildAlertCard(filteredAlerts[index]);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // --- ANALYTICS DASHBOARD ---
  Widget _buildAnalyticsDashboard(AlertController controller) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.analytics_rounded, color: AppColors.primary, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Incident Overview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${controller.resolutionRate.toStringAsFixed(0)}% Resolved',
                      style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Responsive 3-Metric Tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Total Incidents',
                  value: controller.totalAlerts.toString(),
                  icon: Icons.notifications_active_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Resolved',
                  value: controller.resolvedCount.toString(),
                  icon: Icons.verified_user_rounded,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Avg Response',
                  value: controller.averageResolutionTime,
                  icon: Icons.timer_rounded,
                  color: const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),

          // Trigger Source Breakdown Chips (Wrap instead of overflow row)
          const Text(
            'Trigger Sources:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSourceBadge('🎙️ Voice', controller.voiceTriggerCount, const Color(0xFF8B5CF6)),
              _buildSourceBadge('📳 Shake', controller.shakeTriggerCount, const Color(0xFFF59E0B)),
              _buildSourceBadge('🔘 Pendant', controller.pendantTriggerCount, const Color(0xFF06B6D4)),
              _buildSourceBadge('🔴 App Button', controller.buttonTriggerCount, AppColors.sosRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- FILTER TABS ---
  Widget _buildFilterTabs(AlertController controller) {
    final filters = [
      {'key': 'all', 'label': 'All (${controller.totalAlerts})'},
      {'key': 'active', 'label': 'Active (${controller.activeCount})'},
      {'key': 'resolved', 'label': 'Resolved (${controller.resolvedCount})'},
      {'key': 'false_alarm', 'label': 'False Alarm (${controller.falseAlarmCount})'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: InkWell(
              onTap: () => setState(() => _selectedFilter = f['key'] as String),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  f['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- ALERT CARD (COMPLETELY RESIZED & OVERFLOW-SAFE) ---
  Widget _buildAlertCard(PanicEventModel alert) {
    final triggerConfig = _getTriggerConfig(alert.triggerMethod);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Trigger Method + Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: triggerConfig.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(triggerConfig.icon, color: triggerConfig.color, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              triggerConfig.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: triggerConfig.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              DateFormat('MMM dd, yyyy • HH:mm').format(alert.triggeredAt),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(alert.status),
              ],
            ),
            const SizedBox(height: 10),

            // Location Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1.0),
                        child: Icon(Icons.location_on_rounded, color: AppColors.accent, size: 15),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          alert.isLocationAnonymised
                              ? 'Location Anonymised (Kenya DPA 2024 compliance)'
                              : 'Lat ${alert.latitude.toStringAsFixed(5)}, Lng ${alert.longitude.toStringAsFixed(5)} (±${alert.locationAccuracyM.toStringAsFixed(0)}m accuracy)',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 3D Mapbox Live Tracking Replay Actions (Single 3D Mapbox Live Link)
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(AppConstants.buildLiveTrackingUrl(
                              lat: alert.latitude,
                              lng: alert.longitude,
                              alertId: alert.id,
                            ));
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.travel_explore_rounded, size: 14, color: Colors.white),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('⚡ 3D Live Mapbox', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final trackUrl = AppConstants.buildLiveTrackingUrl(
                              lat: alert.latitude,
                              lng: alert.longitude,
                              alertId: alert.id,
                            );
                            await Clipboard.setData(ClipboardData(text: trackUrl));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('3D Mapbox tracking link copied to clipboard!'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Copy Link', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Dispatches / Broadcasts Summary Tags (Using Wrap so it NEVER overflows horizontally)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildDispatchTag(
                  icon: Icons.group_rounded,
                  label: 'Contacts',
                  isDispatched: alert.emergencyContactsNotified,
                ),
                _buildDispatchTag(
                  icon: Icons.shield_rounded,
                  label: 'Responders',
                  isDispatched: alert.communityRespondersAlerted,
                ),
                _buildDispatchTag(
                  icon: Icons.local_police_rounded,
                  label: 'Police 999',
                  isDispatched: alert.hotlineNotified,
                ),
              ],
            ),

            if (alert.notes != null && alert.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Note: ${alert.notes}',
                style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDispatchTag({
    required IconData icon,
    required String label,
    required bool isDispatched,
  }) {
    final color = isDispatched ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            isDispatched ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 9,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status.toLowerCase()) {
      case 'active':
        color = AppColors.sosRed;
        label = 'ACTIVE';
        break;
      case 'resolved':
        color = AppColors.success;
        label = 'RESOLVED';
        break;
      case 'false_alarm':
      default:
        color = AppColors.textSecondary;
        label = 'FALSE ALARM';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }

  _TriggerConfig _getTriggerConfig(String method) {
    switch (method.toLowerCase()) {
      case 'voice_keyword':
        return _TriggerConfig(
          title: 'Voice Activation',
          icon: Icons.mic_rounded,
          color: const Color(0xFF8B5CF6),
        );
      case 'app_shake':
        return _TriggerConfig(
          title: 'Shake Sensor',
          icon: Icons.vibration_rounded,
          color: const Color(0xFFF59E0B),
        );
      case 'pendant_touch':
      case 'wearable':
        return _TriggerConfig(
          title: 'ESP32 Pendant SOS',
          icon: Icons.watch_rounded,
          color: const Color(0xFF06B6D4),
        );
      case 'app_button':
      case 'app':
      default:
        return _TriggerConfig(
          title: 'In-App SOS Button',
          icon: Icons.touch_app_rounded,
          color: AppColors.sosRed,
        );
    }
  }
}

class _TriggerConfig {
  final String title;
  final IconData icon;
  final Color color;

  _TriggerConfig({
    required this.title,
    required this.icon,
    required this.color,
  });
}
