import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../controllers/home_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../emergency/controllers/emergency_controller.dart';

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
    });
  }

  void _showShakeSettingsModal(BuildContext context, EmergencyController emergencyController) {
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: (isArmed ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.vibration_rounded,
                            color: isArmed ? AppColors.success : AppColors.error,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shake Detection Trigger',
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isArmed ? 'ARMED & ACTIVE IN BACKGROUND' : 'DISABLED',
                                style: TextStyle(
                                  color: isArmed ? AppColors.success : AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
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
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.inputBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How it works:',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Vigorously shake your phone 2 or more times to immediately start the 10-second emergency SOS countdown, alert responders, and dispatch your GPS coordinates.',
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/emergency');
                        emergencyController.trigger(TriggerMethod.appShake);
                      },
                      icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        'Test Shake SOS Now',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sosRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _showVoiceSettingsModal(BuildContext context, EmergencyController emergencyController) {
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: (isEnabled ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isListening ? Icons.mic_rounded : (isEnabled ? Icons.mic_rounded : Icons.mic_off_rounded),
                            color: isEnabled ? AppColors.success : AppColors.error,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Voice Keyword SOS',
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isListening
                                    ? 'ACTIVE LISTENING FOR HELP PHRASE'
                                    : (isEnabled ? 'ENABLED (STANDBY)' : 'DISABLED'),
                                style: TextStyle(
                                  color: isEnabled ? AppColors.success : AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
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
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.inputBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergency Wake Words:',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Say any of these phrases out loud to automatically trigger SOS:\n'
                            '• "Help" or "Help me"\n'
                            '• "Send Help"\n'
                            '• "Emergency"\n'
                            '• "Tuma Msaada" or "Msaada" (Kiswahili)\n'
                            '• "Piga Polisi" (Kiswahili)',
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/emergency');
                        emergencyController.trigger(TriggerMethod.voiceKeyword);
                      },
                      icon: const Icon(Icons.record_voice_over_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        'Test Voice SOS Now',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sosRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    final homeController = context.watch<HomeController>();
    final authController = context.watch<AuthController>();
    final emergencyController = context.watch<EmergencyController>();
    final user = homeController.user ?? authController.currentUser;
    final displayName = user?.fullName.isNotEmpty == true ? user!.fullName.split(' ').first : 'Joy';

    final screenWidth = MediaQuery.of(context).size.width;
    final sosButtonSize = min(180.0, screenWidth * 0.45);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Greeting & Avatar Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good morning,',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // Notification Bell with red dot
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications_none_rounded, size: 28, color: context.textPrimary),
                            onPressed: () => Navigator.pushNamed(context, '/alerts'),
                          ),
                          Positioned(
                            right: 12,
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
                      const SizedBox(width: 6),
                      // User Avatar Profile
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/profile'),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/user_avatar.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => CircleAvatar(
                                backgroundColor: context.inputBg,
                                child: const Icon(Icons.person, color: AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Device Status Card (SafeLink Pendant)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: context.isDarkMode ? Colors.black.withValues(alpha: 0.3) : AppColors.cardShadow,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Pendant Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 76,
                        height: 76,
                        color: AppColors.secondary,
                        child: Image.asset(
                          'assets/images/pendant_device.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.watch, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.circle, color: AppColors.success, size: 9),
                              SizedBox(width: 6),
                              Text(
                                'Connected',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'SafeLink Pendant',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: const [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.battery_5_bar_rounded, color: AppColors.primary, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    '78%',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.signal_cellular_alt_rounded, color: AppColors.primary, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Strong',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Last sync: 2 minutes ago',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pushNamed(context, '/shop'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shopping_bag_outlined, size: 12, color: AppColors.primary),
                                      SizedBox(width: 4),
                                      Text(
                                        'Order Pendant',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => Navigator.pushNamed(context, '/wearable'),
                                child: const Text(
                                  'Pairing',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
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
              const SizedBox(height: 24),

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
                        colors: [
                          AppColors.sosRed,
                          Color(0xFFE11D48),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sosRed.withValues(alpha: 0.35),
                          blurRadius: 36,
                          spreadRadius: 6,
                        ),
                        BoxShadow(
                          color: AppColors.sosRed.withValues(alpha: 0.15),
                          blurRadius: 50,
                          spreadRadius: 14,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.fingerprint, color: Colors.white, size: 36),
                          SizedBox(height: 2),
                          Text(
                            'HOLD FOR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // TRIGGER METHODS Header
              const Text(
                'TRIGGER METHODS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 12),

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
                      subtitle: emergencyController.isShakeActive ? 'Active' : 'Disabled',
                      isHighlighted: emergencyController.isShakeActive,
                      onTap: () => _showShakeSettingsModal(context, emergencyController),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTriggerCard(
                      icon: emergencyController.isVoiceActive
                          ? Icons.mic_rounded
                          : (emergencyController.isVoiceEnabled ? Icons.mic_rounded : Icons.mic_none_rounded),
                      title: 'Voice SOS',
                      subtitle: emergencyController.isVoiceActive
                          ? 'Listening'
                          : (emergencyController.isVoiceEnabled ? 'Standby' : 'Disabled'),
                      isHighlighted: emergencyController.isVoiceActive || emergencyController.isVoiceEnabled,
                      onTap: () => _showVoiceSettingsModal(context, emergencyController),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // QUICK ACTIONS Header
              const Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 12),

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
                      onTap: () => Navigator.pushNamed(context, '/voice-settings'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Map'),
            BottomNavigationBarItem(icon: Icon(Icons.warning_amber_rounded), label: 'Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded), label: 'Contacts'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: context.surfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted ? AppColors.success.withValues(alpha: 0.6) : context.cardBorder,
            width: isHighlighted ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: context.isDarkMode ? Colors.black.withValues(alpha: 0.2) : AppColors.cardShadow,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: isHighlighted ? AppColors.success : AppColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHighlighted ? AppColors.success : context.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
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
