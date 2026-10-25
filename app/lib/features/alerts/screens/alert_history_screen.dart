import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/alert_controller.dart';
import '../../../models/panic_event_model.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  String _selectedFilter = 'all'; // 'all', 'active', 'resolved', 'analytics'

  void _open3DMap(double lat, double lon, String? id) async {
    final incidentRef = id ?? 'SOS-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
    final url = 'https://joychepchumba.github.io/gps-safety-wearable/track.html?lat=$lat&lng=$lon&id=$incidentRef';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _openGoogleMaps(double lat, double lon) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lon');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlertController>();

    final filteredAlerts = controller.alerts.where((a) {
      if (_selectedFilter == 'all' || _selectedFilter == 'analytics') return true;
      return a.status.toLowerCase() == _selectedFilter;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Incident History & Telemetry',
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
            tooltip: 'Refresh Incidents',
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- 1. EXECUTIVE ANALYTICS DASHBOARD ---
                    _buildAnalyticsDashboard(controller),
                    const SizedBox(height: 16),

                    // --- 2. FILTER PILLS ---
                    _buildFilterTabs(controller),
                    const SizedBox(height: 16),

                    // If Analytics tab is selected, show deep analytics view
                    if (_selectedFilter == 'analytics')
                      _buildDeepAnalyticsSection(controller)
                    else ...[
                      // --- 3. INCIDENTS LIST ---
                      if (filteredAlerts.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
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
                              const SizedBox(height: 14),
                              Text(
                                _selectedFilter == 'all' ? 'No incidents recorded yet' : 'No $_selectedFilter incidents found',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Emergency dispatches from your wearable or mobile app will appear here with live telemetry.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                            return _buildIncidentCard(filteredAlerts[index], controller);
                          },
                        ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // --- EXECUTIVE ANALYTICS DASHBOARD ---
  Widget _buildAnalyticsDashboard(AlertController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  Icon(Icons.analytics_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Safety Analytics Overview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const SizedBox(height: 14),

          // 3-Metric Tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Total Alerts',
                  value: controller.totalAlerts.toString(),
                  icon: Icons.notifications_active_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Active',
                  value: controller.activeCount.toString(),
                  icon: Icons.emergency_rounded,
                  color: controller.activeCount > 0 ? AppColors.sosRed : AppColors.textMuted,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- FILTER TABS ---
  Widget _buildFilterTabs(AlertController controller) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('all', 'All (${controller.totalAlerts})'),
          const SizedBox(width: 8),
          _buildFilterChip('active', 'Active (${controller.activeCount})', isRed: true),
          const SizedBox(width: 8),
          _buildFilterChip('resolved', 'Resolved (${controller.resolvedCount})'),
          const SizedBox(width: 8),
          _buildFilterChip('analytics', 'Deep Analytics', icon: Icons.insights_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, {bool isRed = false, IconData? icon}) {
    final isSelected = _selectedFilter == value;
    final activeColor = isRed ? AppColors.sosRed : AppColors.primary;

    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- DEEP ANALYTICS SECTION ---
  Widget _buildDeepAnalyticsSection(AlertController controller) {
    int wearableCount = 0;
    int voiceCount = 0;
    int shakeCount = 0;
    int buttonCount = 0;

    for (final a in controller.alerts) {
      final m = a.triggerMethod.toLowerCase();
      if (m.contains('pendant') || m.contains('touch') || m.contains('wearable')) {
        wearableCount++;
      } else if (m.contains('voice')) {
        voiceCount++;
      } else if (m.contains('shake')) {
        shakeCount++;
      } else {
        buttonCount++;
      }
    }

    final total = controller.totalAlerts == 0 ? 1 : controller.totalAlerts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trigger Method Distribution
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_rounded, color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Trigger Source Breakdown',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildProgressRow('Wearable Touch Button', wearableCount, total, const Color(0xFF0066FF)),
              const SizedBox(height: 12),
              _buildProgressRow('Voice SOS Keyword', voiceCount, total, const Color(0xFF8B5CF6)),
              const SizedBox(height: 12),
              _buildProgressRow('Mobile Shake Trigger', shakeCount, total, const Color(0xFFF59E0B)),
              const SizedBox(height: 12),
              _buildProgressRow('Mobile App Button', buttonCount, total, const Color(0xFFFF334B)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Safety Reliability Insights
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Safety Telemetry Reliability',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildInsightItem(
                icon: Icons.satellite_alt_rounded,
                title: 'GPS Satellite Precision',
                desc: 'Outdoor alerts achieve 5m satellite accuracy via NEO-6M receiver.',
              ),
              const SizedBox(height: 10),
              _buildInsightItem(
                icon: Icons.sms_rounded,
                title: 'Cellular SMS Offline Guarantee',
                desc: 'SIM800L dispatches emergency links directly without depending on Wi-Fi.',
              ),
              const SizedBox(height: 10),
              _buildInsightItem(
                icon: Icons.map_rounded,
                title: '3D Mapbox Volumetric Telemetry',
                desc: 'Extruded buildings and terrain give guardians immediate spatial awareness.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow(String label, int count, int total, Color color) {
    final pct = (count / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('$count (${(pct * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightItem({required IconData icon, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  // --- INCIDENT CARD ---
  Widget _buildIncidentCard(PanicEventModel alert, AlertController controller) {
    final isActive = alert.status.toLowerCase() == 'active';
    final lat = alert.latitude;
    final lon = alert.longitude;
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(alert.triggeredAt.toLocal());

    // Determine trigger info
    String triggerTitle = 'Emergency Button';
    IconData triggerIcon = Icons.touch_app_rounded;
    Color triggerColor = AppColors.sosRed;

    final tm = alert.triggerMethod.toLowerCase();
    if (tm.contains('pendant') || tm.contains('touch') || tm.contains('wearable')) {
      triggerTitle = 'Wearable Touch Sensor';
      triggerIcon = Icons.watch_rounded;
      triggerColor = const Color(0xFF0066FF);
    } else if (tm.contains('voice')) {
      triggerTitle = 'Voice SOS Keyword';
      triggerIcon = Icons.mic_rounded;
      triggerColor = const Color(0xFF8B5CF6);
    } else if (tm.contains('shake')) {
      triggerTitle = 'Mobile Shake Trigger';
      triggerIcon = Icons.vibration_rounded;
      triggerColor = const Color(0xFFF59E0B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? AppColors.sosRed.withValues(alpha: 0.5) : AppColors.border,
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive ? AppColors.sosRed.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: triggerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(triggerIcon, color: triggerColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        triggerTitle,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.sosRed.withValues(alpha: 0.12) : AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? Icons.emergency_rounded : Icons.check_circle_rounded,
                        color: isActive ? AppColors.sosRed : AppColors.success,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'ACTIVE' : 'RESOLVED',
                        style: TextStyle(
                          color: isActive ? AppColors.sosRed : AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Body with Location & Notes
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Coordinates: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                if (alert.notes != null && alert.notes!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      alert.notes!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Action Buttons (3D Mapbox, Google Maps, Resolve)
                Row(
                  children: [
                    // 3D Mapbox Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _open3DMap(lat, lon, alert.id),
                        icon: const Icon(Icons.view_in_ar_rounded, size: 16, color: Colors.white),
                        label: const Text('Live 3D Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Google Maps Button
                    OutlinedButton(
                      onPressed: () => _openGoogleMaps(lat, lon),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: const Icon(Icons.map_rounded, size: 16, color: AppColors.textPrimary),
                    ),

                    if (isActive) ...[
                      const SizedBox(width: 8),
                      // Resolve Button
                      OutlinedButton(
                        onPressed: () async {
                          await controller.resolveAlert(alert.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Incident marked as resolved.'), backgroundColor: AppColors.success),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: const BorderSide(color: AppColors.success),
                        ),
                        child: const Text('Resolve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
