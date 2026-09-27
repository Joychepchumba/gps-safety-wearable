import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../models/user_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _duressPinController;
  bool _isCommunityResponder = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final authController = context.read<AuthController>();
    final user = authController.currentUser;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    _duressPinController = TextEditingController();
    _isCommunityResponder = user?.isCommunityResponder ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _duressPinController.dispose();
    super.dispose();
  }

  void _syncUserToControllers(UserModel? user) {
    if (!_isEditing && user != null) {
      if (_nameController.text != user.fullName) {
        _nameController.text = user.fullName;
      }
      if (_phoneController.text != user.phoneNumber) {
        _phoneController.text = user.phoneNumber;
      }
      _isCommunityResponder = user.isCommunityResponder;
    }
  }

  Future<void> _saveProfile(AuthController authController) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final success = await authController.updateProfile(
      fullName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      isCommunityResponder: _isCommunityResponder,
      emergencyPassword: _duressPinController.text.trim().isNotEmpty
          ? _duressPinController.text.trim()
          : null,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _isEditing = false;
          _duressPinController.clear();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Profile updated successfully!' : 'Failed to update profile. Please try again.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  void _confirmLogout(BuildContext context, AuthController authController) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to log out of SafeLink? In an emergency, staying signed in ensures instant SOS triggering.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              authController.logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sosRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final user = authController.currentUser;
    _syncUserToControllers(user);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
              label: const Text(
                'Edit',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            )
          else
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _syncUserToControllers(user);
                  _duressPinController.clear();
                });
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Avatar & Badges Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        const CircleAvatar(
                          radius: 42,
                          backgroundImage: AssetImage('assets/images/user_avatar.jpg'),
                          backgroundColor: AppColors.inputBg,
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.fullName.isNotEmpty == true ? user!.fullName : 'SafeLink User',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email.isNotEmpty == true ? user!.email : 'No email provided',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (user?.phoneNumber.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        user!.phoneNumber,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (user?.isCommunityResponder ?? false)
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.inputBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (user?.isCommunityResponder ?? false)
                                    ? Icons.health_and_safety_rounded
                                    : Icons.person_outline_rounded,
                                size: 14,
                                color: (user?.isCommunityResponder ?? false)
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (user?.isCommunityResponder ?? false)
                                    ? 'COMMUNITY RESPONDER'
                                    : 'STANDARD MEMBER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: (user?.isCommunityResponder ?? false)
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (user?.hasEmergencyPassword ?? false) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.warning),
                                SizedBox(width: 4),
                                Text(
                                  'DURESS PIN SET',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Edit Form or Details Card
              if (_isEditing) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.edit_note_rounded, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text(
                              'Edit Profile Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Full Name
                        const Text(
                          'Full Name',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Name is required' : null,
                          decoration: InputDecoration(
                            hintText: 'Your Full Name',
                            prefixIcon: const Icon(Icons.person_outline, size: 20, color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Phone Number
                        const Text(
                          'Phone Number',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Phone number is required' : null,
                          decoration: InputDecoration(
                            hintText: '+254 700 000 000',
                            prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Community Responder Switch
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Community Responder',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Receive notifications if someone nearby triggers an emergency alert.',
                                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isCommunityResponder,
                                activeTrackColor: AppColors.primary,
                                activeThumbColor: Colors.white,
                                onChanged: (val) => setState(() => _isCommunityResponder = val),
                              ),


                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Secret Duress Password
                        const Text(
                          'Update Secret Duress PIN (Optional)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Used to trigger a silent covert SOS alarm if forced under threat.',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _duressPinController,
                          obscureText: true,
                          keyboardType: TextInputType.text,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Leave blank to keep existing',
                            prefixIcon: const Icon(Icons.shield_outlined, size: 20, color: AppColors.warning),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Save Button
                        _isSaving
                            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                            : ElevatedButton(
                                onPressed: () => _saveProfile(authController),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Quick Actions List
              const Text(
                'SAFETY PREFERENCES & FEATURES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              _buildMenuCard(
                icon: Icons.shopping_bag_outlined,
                iconColor: AppColors.primary,
                title: 'SafeLink Pendant Store',
                subtitle: 'Order smart jewelry with GPS & 7-day battery',
                badge: 'KES 3,500',
                onTap: () => Navigator.pushNamed(context, '/shop'),
              ),
              const SizedBox(height: 10),

              _buildMenuCard(
                icon: Icons.contact_phone_outlined,
                iconColor: AppColors.accent,
                title: 'Emergency Contacts',
                subtitle: 'Manage 3 trusted guardians notified during SOS',
                onTap: () => Navigator.pushNamed(context, '/contacts'),
              ),
              const SizedBox(height: 10),

              _buildMenuCard(
                icon: Icons.lock_clock_outlined,
                iconColor: AppColors.warning,
                title: 'Reset Password via 6-digit OTP',
                subtitle: 'Send one-time security code to your email',
                onTap: () => Navigator.pushNamed(context, '/reset-password'),
              ),
              const SizedBox(height: 10),

              _buildMenuCard(
                icon: Icons.security_rounded,
                iconColor: AppColors.success,
                title: 'Security & Two-Factor Auth (MFA)',
                subtitle: 'TOTP Authenticator app protection',
                onTap: () => Navigator.pushNamed(context, '/mfa-setup'),
              ),
              const SizedBox(height: 10),

              _buildMenuCard(
                icon: Icons.bluetooth_searching_rounded,
                iconColor: AppColors.secondary,
                title: 'Wearable Hardware Pairing',
                subtitle: 'Pair physical smart pendant via BLE',
                onTap: () => Navigator.pushNamed(context, '/wearable'),
              ),
              const SizedBox(height: 28),

              // Log Out Button
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, authController),
                icon: const Icon(Icons.logout_rounded, color: AppColors.sosRed, size: 20),
                label: const Text(
                  'Log Out of SafeLink',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.sosRed,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.sosRed, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: AppColors.sosRed.withValues(alpha: 0.04),
                ),
              ),
              const SizedBox(height: 20),

              // App Version info
              const Center(
                child: Text(
                  'SafeLink v1.0.0 • Protected by End-to-End Safety Protocol',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
