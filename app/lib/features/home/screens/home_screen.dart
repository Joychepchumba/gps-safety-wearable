import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/theme/theme_controller.dart';
import '../controllers/home_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../emergency/controllers/emergency_controller.dart';
import '../../emergency/services/voice_activation_service.dart';
import '../../wearable/controllers/wearable_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final emergencyController = context.read<EmergencyController>();
      emergencyController.startProtection();
      context.read<HomeController>().loadUser();
      context.read<AuthController>().refreshProfile();
    });
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning,';
    } else if (hour >= 12 && hour < 16) {
      return 'Good afternoon,';
    } else {
      return 'Good evening,';
    }
  }

  String _getDisplayName(dynamic user) {
    if (user != null) {
      final fullName = user.fullName as String?;
      if (fullName != null &&
          fullName.trim().isNotEmpty &&
          fullName.trim() != 'SafeLink User') {
        return fullName.trim();
      }
      final email = user.email as String?;
      if (email != null && email.contains('@')) {
        final prefix = email.split('@').first.trim();
        if (prefix.isNotEmpty) {
          return prefix[0].toUpperCase() + prefix.substring(1);
        }
      }
    }
    return 'Guardian';
  }

  void _showShakeSettingsModal(
    BuildContext context,
    EmergencyController emergencyController,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final isArmed = emergencyController.isShakeActive;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: modalContext.cardBorder,
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
                            color:
                                (isArmed ? AppColors.success : AppColors.error)
                                    .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.vibration_rounded,
                            color: isArmed
                                ? AppColors.success
                                : AppColors.error,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shake Detection Trigger',
                                style: TextStyle(
                                  color: modalContext.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isArmed
                                    ? 'ARMED & ACTIVE IN BACKGROUND'
                                    : 'DISABLED',
                                style: TextStyle(
                                  color: isArmed
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isArmed,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) {
                            emergencyController.toggleShakeDetection();
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: modalContext.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: modalContext.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How it works:',
                            style: TextStyle(
                              color: modalContext.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vigorously shake your phone 2 or more times to immediately start the emergency SOS countdown, alert responders, and dispatch your GPS coordinates.',
                            style: TextStyle(
                              color: modalContext.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/emergency');
                        emergencyController.trigger(TriggerMethod.appShake);
                      },
                      icon: const Icon(
                        Icons.flash_on_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Test Shake SOS Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sosRed,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showVoiceSettingsModal(
    BuildContext context,
    EmergencyController emergencyController,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final isEnabled = emergencyController.isVoiceEnabled;
            final isListening = emergencyController.isVoiceActive;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: modalContext.cardBorder,
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
                            color:
                                (isEnabled
                                        ? AppColors.success
                                        : AppColors.error)
                                    .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isListening
                                ? Icons.mic_rounded
                                : (isEnabled
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded),
                            color: isEnabled
                                ? AppColors.success
                                : AppColors.error,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Voice Keyword SOS',
                                style: TextStyle(
                                  color: modalContext.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isListening
                                    ? 'ACTIVE LISTENING FOR HELP PHRASE'
                                    : (isEnabled
                                          ? 'ENABLED (STANDBY)'
                                          : 'DISABLED'),
                                style: TextStyle(
                                  color: isEnabled
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) async {
                            await emergencyController.toggleVoiceDetection();
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: modalContext.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: modalContext.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergency Wake Words:',
                            style: TextStyle(
                              color: modalContext.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Say any of these phrases out loud to automatically trigger SOS:\n'
                            '• "Help" or "Help me"\n'
                            '• "Send Help" or "Emergency"\n'
                            '• "Tuma Msaada" or "Msaada" (Kiswahili)\n'
                            '• "Piga Polisi" (Kiswahili)',
                            style: TextStyle(
                              color: modalContext.textSecondary,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pushNamed(context, '/voice-settings');
                            },
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Voice Settings'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pushNamed(context, '/emergency');
                              emergencyController.trigger(
                                TriggerMethod.voiceKeyword,
                              );
                            },
                            icon: const Icon(
                              Icons.record_voice_over_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'Test Voice SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sosRed,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final homeController = context.watch<HomeController>();
    final authController = context.watch<AuthController>();
    final emergencyController = context.watch<EmergencyController>();
    final user = authController.currentUser ?? homeController.user;
    final displayName = _getDisplayName(user);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenWidth < 360 || screenHeight < 680;
    final sosButtonSize = isCompact
        ? min(136.0, screenWidth * 0.36)
        : min(156.0, screenWidth * 0.40);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Greeting, Theme Switcher & Avatar Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTimeGreeting(),
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Light / Dark Mode Quick Toggle
                      IconButton(
                        tooltip: context.isDarkMode
                            ? 'Switch to Light Mode'
                            : 'Switch to Dark Mode',
                        icon: Icon(
                          context.isDarkMode
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 22,
                          color: context.textPrimary,
                        ),
                        onPressed: () => themeController.toggleDarkMode(),
                      ),
                      // Notification Bell with red dot
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.notifications_none_rounded,
                              size: 25,
                              color: context.textPrimary,
                            ),
                            onPressed: () =>
                                Navigator.pushNamed(context, '/alerts'),
                          ),
                          Positioned(
                            right: 11,
                            top: 10,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.sosRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      // User Avatar Profile (synced with ProfileScreen via AvatarPresets)
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/profile').then((_) {
                            if (context.mounted) {
                              context.read<AuthController>().refreshProfile();
                              context.read<HomeController>().loadUser();
                            }
                          });
                        },
                        child: AvatarPresets.renderWidget(
                          avatarId: user?.avatarUrl,
                          fallbackName: user?.fullName ?? displayName,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Voice Keyword Detection Banner (shows only when a wake word is detected)
              ValueListenableBuilder<String?>(
                valueListenable:
                    VoiceActivationService.instance.lastDetectedKeyword,
                builder: (context, detectedKeyword, _) {
                  if (detectedKeyword == null || detectedKeyword.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sosRed.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.sosRed, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.record_voice_over_rounded,
                          color: AppColors.sosRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VOICE KEYWORD DETECTED!',
                                style: TextStyle(
                                  color: AppColors.sosRed,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              Text(
                                'Heard: "$detectedKeyword" — Emergency SOS Triggered',
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: context.textSecondary,
                          ),
                          onPressed: () {
                            VoiceActivationService
                                    .instance
                                    .lastDetectedKeyword
                                    .value =
                                null;
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Device Status Card (SafeLink Pendant -> taps to My Pendant & Parental Controls)
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/wearable'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: context.isDarkMode
                            ? Colors.black.withValues(alpha: 0.25)
                            : AppColors.cardShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Pendant Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 68,
                          height: 68,
                          color: AppColors.secondary,
                          child: Image.asset(
                            'assets/images/pendant_device.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.watch,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  color: AppColors.success,
                                  size: 8,
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: context.textMuted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SafeLink Pendant #JK001',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.signal_cellular_alt_rounded,
                                      color: AppColors.primary,
                                      size: 15,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Strong',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '• Parent & Locate',
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      Navigator.pushNamed(context, '/wearable'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.tune_rounded,
                                          size: 11,
                                          color: AppColors.primary,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Pendant Controls',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      Navigator.pushNamed(context, '/shop'),
                                  child: Text(
                                    'Order Pendant',
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '💡 Sending Blink command to ESP32 LED (GPIO8)...',
                                              ),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                      final sent = await context
                                          .read<WearableController>()
                                          .findPendantLedStrobe();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  sent
                                                      ? '✅ ESP32 LED (GPIO8) is blinking!'
                                                      : '⚠️ Pendant not connected over BLE. Turn on Bluetooth & bring pendant close.',
                                                ),
                                                backgroundColor: sent
                                                    ? AppColors.success
                                                    : AppColors.warning,
                                                duration: const Duration(
                                                  seconds: 3,
                                                ),
                                              ),
                                            );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 7,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.amber.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.lightbulb_rounded,
                                            size: 14,
                                            color: Colors.amber,
                                          ),
                                          SizedBox(width: 5),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'Blink LED',
                                                style: TextStyle(
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '🚨 Triggering ESP32 Pendant SOS...',
                                              ),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                      await context
                                          .read<WearableController>()
                                          .triggerRemotePendantSos();
                                      if (context.mounted) {
                                        context
                                            .read<EmergencyController>()
                                            .trigger(
                                              TriggerMethod.pendantTouch,
                                            );
                                        Navigator.pushNamed(
                                          context,
                                          '/emergency',
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 7,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.sosRed.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.sosRed.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.sos_rounded,
                                            size: 15,
                                            color: AppColors.sosRed,
                                          ),
                                          SizedBox(width: 5),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'Trigger Pendant',
                                                style: TextStyle(
                                                  color: AppColors.sosRed,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11.5,
                                                ),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Central Glowing SOS Button
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/emergency'),
                  child: Container(
                    width: sosButtonSize,
                    height: sosButtonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [AppColors.sosRed, Color(0xFFE11D48)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sosRed.withValues(alpha: 0.32),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: AppColors.sosRed.withValues(alpha: 0.12),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            color: Colors.white,
                            size: 32,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'HOLD FOR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // TRIGGER METHODS Header
              const Text(
                'TRIGGER METHODS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // Trigger Methods Cards Row
              Row(
                children: [
                  Expanded(
                    child: _buildTriggerCard(
                      icon: Icons.wifi_tethering_rounded,
                      title: 'Tap Pendant',
                      subtitle: 'Connected',
                      onTap: () => Navigator.pushNamed(context, '/wearable'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTriggerCard(
                      icon: Icons.vibration_rounded,
                      title: 'Shake Phone',
                      subtitle: emergencyController.isShakeActive
                          ? 'Active'
                          : 'Disabled',
                      isHighlighted: emergencyController.isShakeActive,
                      onTap: () =>
                          _showShakeSettingsModal(context, emergencyController),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTriggerCard(
                      icon: emergencyController.isVoiceActive
                          ? Icons.mic_rounded
                          : (emergencyController.isVoiceEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded),
                      title: 'Voice SOS',
                      subtitle: emergencyController.isVoiceActive
                          ? 'Listening'
                          : (emergencyController.isVoiceEnabled
                                ? 'Standby'
                                : 'Disabled'),
                      isHighlighted:
                          emergencyController.isVoiceActive ||
                          emergencyController.isVoiceEnabled,
                      onTap: () =>
                          _showVoiceSettingsModal(context, emergencyController),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // QUICK ACTIONS Header
              const Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // Responsive Quick Actions Row (NO OVERFLOW)
              Row(
                children: [
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.navigation_outlined,
                      label: 'Share location',
                      onTap: () => Navigator.pushNamed(context, '/map'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.phone_outlined,
                      label: 'Call contact',
                      onTap: () => Navigator.pushNamed(context, '/contacts'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.history_rounded,
                      label: 'Alert history',
                      onTap: () => Navigator.pushNamed(context, '/alerts'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.mic_rounded,
                      label: 'Voice SOS',
                      onTap: () =>
                          Navigator.pushNamed(context, '/voice-settings'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Community Responder & BLE Distress Radar Card
              InkWell(
                onTap: () =>
                    Navigator.pushNamed(context, '/community-responders'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: AppColors.success,
                          size: 20,
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
                                    'Community Responders & BLE Radar',
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'BLE + GPS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Live map of your location & nearby users in distress',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.scaffoldBg,
          border: Border(top: BorderSide(color: context.cardBorder, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: context.scaffoldBg,
          elevation: 0,
          currentIndex: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: context.textMuted,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warning_amber_rounded),
              label: 'Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              label: 'Contacts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Profile',
            ),
          ],
          onTap: (index) {
            if (index == 1) Navigator.pushNamed(context, '/map');
            if (index == 2) Navigator.pushNamed(context, '/alerts');
            if (index == 3) Navigator.pushNamed(context, '/contacts');
            if (index == 4) Navigator.pushNamed(context, '/profile');
          },
        ),
      ),
    );
  }

  Widget _buildTriggerCard({
    required IconData icon,
    required String title,
    String? subtitle,
    bool isHighlighted = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted
                ? AppColors.success.withValues(alpha: 0.6)
                : context.cardBorder,
            width: isHighlighted ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: context.isDarkMode
                  ? Colors.black.withValues(alpha: 0.2)
                  : AppColors.cardShadow,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isHighlighted ? AppColors.success : AppColors.primary,
              size: 22,
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  style: TextStyle(
                    color: isHighlighted ? AppColors.success : context.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
