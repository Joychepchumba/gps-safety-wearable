import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/theme_controller.dart';
import '../controllers/emergency_controller.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<EmergencyController>();
      if (controller.state != EmergencyState.countdown && controller.state != EmergencyState.sending) {
        controller.trigger(TriggerMethod.button);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeController>();
    final controller = context.watch<EmergencyController>();

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStateContent(context, controller),
        ),
      ),
    );
  }

  Widget _buildStateContent(BuildContext context, EmergencyController controller) {
    switch (controller.state) {
      case EmergencyState.countdown:
        return _buildCountdown(context, controller);
      case EmergencyState.sending:
        return _buildSending(context);
      case EmergencyState.sent:
        return _buildSent(context, controller);
      case EmergencyState.failed:
        return _buildFailed(context, controller);
      case EmergencyState.cancelled:
        return _buildCancelled(context);
      case EmergencyState.idle:
      default:
        return const SizedBox();
    }
  }

  Widget _buildCountdown(BuildContext context, EmergencyController controller) {
    final isShake = controller.lastTriggerMethod == TriggerMethod.appShake;
    final isVoice = controller.lastTriggerMethod == TriggerMethod.voiceKeyword;
    final isPendant = controller.lastTriggerMethod == TriggerMethod.pendantTouch;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isShake) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.sosRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.vibration_rounded, color: AppColors.sosRed, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'SHAKE DETECTING',
                      style: TextStyle(
                        color: AppColors.sosRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (isVoice) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.sosRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, color: AppColors.sosRed, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'VOICE DETECTING',
                      style: TextStyle(
                        color: AppColors.sosRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (isPendant) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.sosRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.sosRed.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_connected_rounded, color: AppColors.sosRed, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'PENDANT SOS ACTIVATED',
                      style: TextStyle(
                        color: AppColors.sosRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'SENDING SOS IN',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${controller.countdownSeconds}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            OutlinedButton(
              onPressed: () => controller.cancel(),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.textPrimary,
                side: BorderSide(color: context.cardBorder, width: 2),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text(
                AppStrings.cancelBtn,
                style: TextStyle(fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSending(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 24),
            Text(
              AppStrings.sendingAlert,
              style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSent(BuildContext context, EmergencyController controller) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 84),
            const SizedBox(height: 20),
            Text(
              AppStrings.emergencyAlertSent,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Emergency contacts and nearby community responders have been alerted with your real-time GPS coordinates.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 36),
            ElevatedButton(
              onPressed: () {
                if (controller.activeEvent != null) {
                  controller.resolveAlert(controller.activeEvent!.id);
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('I am safe', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailed(BuildContext context, EmergencyController controller) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 80),
            const SizedBox(height: 20),
            Text(
              'Failed to send alert',
              style: TextStyle(color: context.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 36),
            ElevatedButton(
              onPressed: () => controller.trigger(TriggerMethod.button),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Retry Alert', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelled(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: context.textSecondary, size: 70),
            const SizedBox(height: 16),
            Text(
              'Alert Cancelled',
              style: TextStyle(color: context.textSecondary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
