import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/home_controller.dart';
import '../../auth/controllers/auth_controller.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final homeController = context.watch<HomeController>();
    final authController = context.watch<AuthController>();
    final user = homeController.user ?? authController.currentUser;
    final displayName = user?.fullName.isNotEmpty == true ? user!.fullName.split(' ').first : 'Joy';

    return Scaffold(
      backgroundColor: AppColors.background,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Good morning,',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Notification Bell with red dot
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_none_rounded, size: 28, color: AppColors.textPrimary),
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
                              errorBuilder: (context, error, stackTrace) => const CircleAvatar(
                                backgroundColor: AppColors.inputBg,
                                child: Icon(Icons.person, color: AppColors.primary),
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 12,
                      offset: Offset(0, 4),
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
                          const Text(
                            'SafeLink Pendant',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: const [
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
                              SizedBox(width: 14),
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
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
              const SizedBox(height: 28),

              // Central Glowing SOS Button
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/emergency'),
                  child: Container(
                    width: 190,
                    height: 190,
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
                          spreadRadius: 8,
                        ),
                        BoxShadow(
                          color: AppColors.sosRed.withValues(alpha: 0.15),
                          blurRadius: 54,
                          spreadRadius: 18,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.fingerprint, color: Colors.white, size: 40),
                          SizedBox(height: 4),
                          Text(
                            'HOLD FOR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
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
              const SizedBox(height: 32),

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
                      onTap: () => Navigator.pushNamed(context, '/wearable'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTriggerCard(
                      icon: Icons.vibration_rounded,
                      title: 'Shake Phone',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Shake detection is active in background')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTriggerCard(
                      icon: Icons.mic_none_rounded,
                      title: 'Say Help',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Voice keyword "Help" detection listening')),
                        );
                      },
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
              const SizedBox(height: 14),

              // Quick Actions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickAction(
                    icon: Icons.navigation_outlined,
                    label: 'Share location',
                    onTap: () => Navigator.pushNamed(context, '/map'),
                  ),
                  _buildQuickAction(
                    icon: Icons.phone_outlined,
                    label: 'Call contact',
                    onTap: () => Navigator.pushNamed(context, '/contacts'),
                  ),
                  _buildQuickAction(
                    icon: Icons.history_rounded,
                    label: 'Alert history',
                    onTap: () => Navigator.pushNamed(context, '/alerts'),
                  ),
                  _buildQuickAction(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => Navigator.pushNamed(context, '/mfa-setup'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          currentIndex: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 26),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

