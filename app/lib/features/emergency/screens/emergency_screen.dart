import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
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
      context.read<EmergencyController>().trigger(TriggerMethod.button);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EmergencyController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _buildStateContent(controller),
        ),
      ),
    );
  }

  Widget _buildStateContent(EmergencyController controller) {
    switch (controller.state) {
      case EmergencyState.countdown:
        return _buildCountdown(controller);
      case EmergencyState.sending:
        return _buildSending();
      case EmergencyState.sent:
        return _buildSent(controller);
      case EmergencyState.failed:
        return _buildFailed(controller);
      case EmergencyState.cancelled:
        return _buildCancelled();
      case EmergencyState.idle:
      default:
        return const SizedBox();
    }
  }

  Widget _buildCountdown(EmergencyController controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'SENDING SOS IN',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 50,
                  spreadRadius: 15,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${controller.countdownSeconds}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 84,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 60),
        OutlinedButton(
          onPressed: () => controller.cancel(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text(
            AppStrings.cancelBtn,
            style: TextStyle(fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildSending() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 24),
          Text(
            AppStrings.sendingAlert,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(EmergencyController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 100),
            const SizedBox(height: 20),
            const Text(
              AppStrings.emergencyAlertSent,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Emergency contacts and nearby community responders have been alerted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {
                if (controller.activeEvent != null) {
                  controller.resolveAlert(controller.activeEvent!.id);
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('I am safe', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailed(EmergencyController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 90),
            const SizedBox(height: 20),
            const Text(
              'Failed to send alert',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () => controller.trigger(TriggerMethod.button),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Retry Alert', style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelled() {
    return const Center(
      child: Text(
        'Alert Cancelled',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 22),
      ),
    );
  }
}
