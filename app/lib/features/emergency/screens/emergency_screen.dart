import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/emergency_controller.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<EmergencyController>();
      if (ctrl.state == EmergencyState.idle) {
        ctrl.trigger(TriggerMethod.button);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _callPolice() async {
    final uri = Uri.parse('tel:999');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EmergencyController>();

    // Full emergency page has an ominous red emergency gradient
    return PopScope(
      canPop: controller.state == EmergencyState.idle || controller.state == EmergencyState.cancelled,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && controller.state == EmergencyState.countdown) {
          controller.cancel();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0003),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF2B0006),
                Color(0xFF140003),
                Color(0xFF000000),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _buildStateContent(controller),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(EmergencyController controller) {
    switch (controller.state) {
      case EmergencyState.countdown:
        return _buildCountdown(controller);
      case EmergencyState.sending:
        return _buildSending(controller);
      case EmergencyState.sent:
        return _buildSent(controller);
      case EmergencyState.failed:
        return _buildFailed(controller);
      case EmergencyState.cancelled:
        return _buildCancelled(controller);
      case EmergencyState.idle:
      default:
        return const SizedBox();
    }
  }

  Widget _buildCountdown(EmergencyController controller) {
    final isShake = controller.activeTriggerMethod == TriggerMethod.appShake;
    final isVoice = controller.activeTriggerMethod == TriggerMethod.voice;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Emergency trigger banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.sosRed.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isShake
                      ? Icons.vibration_rounded
                      : isVoice
                          ? Icons.mic_rounded
                          : Icons.emergency_rounded,
                  color: AppColors.sosRed,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isShake
                      ? '📳 SHAKE DETECTED'
                      : isVoice
                          ? '🎙️ VOICE ACTIVATED'
                          : '🚨 SOS TRIGGERED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Pulsing Siren Countdown Circle
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFFF1744),
                    Color(0xFFD50000),
                    Color(0xFF8B0000),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF1744).withValues(alpha: 0.5),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${controller.countdownSeconds}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 82,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    const Text(
                      'SECONDS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Clarification text
          Text(
            isShake
                ? 'Did you shake your phone accidentally?'
                : isVoice
                    ? 'Voice distress detected! Sending alert...'
                    : 'Dispatching Emergency Alert...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isShake
                ? 'Your phone is vibrating in emergency mode. Tap CANCEL below within ${controller.countdownSeconds}s if this was accidental.'
                : 'Alerting emergency contacts and community responders within 2 km.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              height: 1.4,
            ),
          ),

          const Spacer(),

          // Big Cancel Button (Prominent & White for unmistakable contrast)
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () => controller.cancel(),
              icon: const Icon(Icons.cancel_rounded, color: AppColors.sosRed, size: 28),
              label: const Text(
                'CANCEL ALERT (I\'M SAFE)',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w900,
                  color: AppColors.sosRed,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 8,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Send Immediately Button (if real emergency and user doesn't want to wait)
          TextButton.icon(
            onPressed: () => controller.sendImmediately(),
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white70, size: 18),
            label: const Text(
              'SEND SOS IMMEDIATELY',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSending(EmergencyController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.sosRed.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.sosRed,
                  strokeWidth: 4,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'BROADCASTING DISTRESS...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Acquiring real-time GPS coordinates and dispatching SMS alerts to guardians & 2 km community responders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSent(EmergencyController controller) {
    final methodStr = switch (controller.activeTriggerMethod) {
      TriggerMethod.voice => '🎙️ Hands-Free Voice Wake Word',
      TriggerMethod.appShake => '📳 3-Hard Shake Sensor Detection',
      TriggerMethod.pendantTouch => '💍 SafeLink Smart Pendant BLE',
      TriggerMethod.duressPin => '🔒 Duress Covert Security PIN',
      TriggerMethod.button => '🚨 In-App Emergency Button',
    };

    final lat = controller.activeEvent?.latitude ?? -1.2825;
    final lng = controller.activeEvent?.longitude ?? 36.8222;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // Header Status Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sosRed,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sosRed.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'SOS BROADCAST ACTIVE & LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Giant Alert Icon
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF2A0808),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.sosRed, width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF10B981),
                size: 58,
              ),
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'EMERGENCY ALERT SENT!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            methodStr,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 24),

          // Active Confirmations Checklist
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF220306),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DISPATCH CONFIRMATION',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),

                _buildConfirmationItem(
                  icon: Icons.mark_chat_read_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Emergency Contacts Notified',
                  subtitle: 'SMS sent to your designated guardians with your real-time tracking link.',
                ),
                const Divider(color: Colors.white12, height: 22),

                _buildConfirmationItem(
                  icon: Icons.groups_rounded,
                  iconColor: const Color(0xFF38BDF8),
                  title: '2 km Community Responders Alerted',
                  subtitle: 'Volunteers and nearby responders within 2,000m received your distress signal.',
                ),
                const Divider(color: Colors.white12, height: 22),

                _buildConfirmationItem(
                  icon: Icons.gps_fixed_rounded,
                  iconColor: const Color(0xFFFBBF24),
                  title: 'Live GPS Coordinates',
                  subtitle: 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)} (Broadcasted)',
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3D Mapbox Real-Time Tracking Link Card (8-Hour Default Session)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF16192E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: controller.isSharingLocation
                    ? const Color(0xFF10B981).withValues(alpha: 0.6)
                    : Colors.white24,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: controller.isSharingLocation
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : Colors.black26,
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: controller.isSharingLocation
                            ? const Color(0xFF10B981)
                            : Colors.orangeAccent,
                        boxShadow: [
                          if (controller.isSharingLocation)
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '3D MAPBOX LIVE TRACKING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: controller.isSharingLocation
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: controller.isSharingLocation
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : Colors.white24,
                        ),
                      ),
                      child: Text(
                        controller.isSharingLocation ? '8-HOUR BEACON ACTIVE' : 'SHARING PAUSED',
                        style: TextStyle(
                          color: controller.isSharingLocation
                              ? const Color(0xFF10B981)
                              : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  controller.isSharingLocation
                      ? 'Live 3D telemetry is actively pinging every 8s. Guardians & responders can follow your altitude, speed, nearby police, and building extrusions.'
                      : 'You paused live location sharing. Responders still retain your last broadcasted GPS coordinates.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (controller.activeTrackingUrl != null) ...[
                  const SizedBox(height: 12),
                  // Link Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.activeTrackingUrl!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: controller.activeTrackingUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('3D Tracking link copied to clipboard!'),
                                backgroundColor: Color(0xFF10B981),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Action buttons: Share Link + Cancel Sharing
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            SharePlus.instance.share(
                              ShareParams(
                                text: '🚨 EMERGENCY: I have activated SafeLink SOS. Track my real-time 3D location, status and nearby units here:\n${controller.activeTrackingUrl!}',
                                subject: '🚨 SafeLink Emergency Live 3D Tracking',
                              ),
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                          label: const Text(
                            'SHARE LINK',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (controller.isSharingLocation)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await controller.cancelRealTimeSharing();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Live location sharing cancelled.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.white70),
                            label: const Text(
                              'CANCEL SHARING',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons
          // 1. I AM SAFE (Resolve Alert)
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                if (controller.activeEvent != null) {
                  controller.resolveAlert(controller.activeEvent!.id);
                } else {
                  controller.state = EmergencyState.idle;
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Emergency alert marked resolved. You are safe!'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
              label: const Text(
                'I AM SAFE (RESOLVE SOS)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 2. View on Map & Call Police Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/map');
                  },
                  icon: const Icon(Icons.map_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'VIEW ON MAP',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.white38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _callPolice,
                  icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'CALL 999 POLICE',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sosRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildConfirmationItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFailed(EmergencyController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.sosRed.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: AppColors.sosRed, size: 70),
            ),
            const SizedBox(height: 20),
            const Text(
              'NETWORK ALERT DISPATCH DELAY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Direct connection timed out. Please call emergency services directly or tap retry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => controller.trigger(controller.activeTriggerMethod),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('RETRY SOS DISPATCH', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sosRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _callPolice,
                icon: const Icon(Icons.phone_rounded, color: Colors.white),
                label: const Text('CALL 999 DIRECTLY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelled(EmergencyController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 76),
          ),
          const SizedBox(height: 20),
          const Text(
            'ALERT CANCELLED',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Text(
            'No emergency alert was sent. You are safe.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
