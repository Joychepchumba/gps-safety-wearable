import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../../emergency/controllers/emergency_controller.dart';
import '../controllers/wearable_controller.dart';

class WearableScreen extends StatefulWidget {
  const WearableScreen({super.key});

  @override
  State<WearableScreen> createState() => _WearableScreenState();
}

class _WearableScreenState extends State<WearableScreen> {
  void _showPhoneSettingsSheet(BuildContext context, WearableController controller) {
    final pendantPhoneCtrl = TextEditingController(text: controller.pendantSimNumber);
    final guardianPhoneCtrl = TextEditingController(text: controller.guardianPhone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Pendant & Parental Settings',
                          style: TextStyle(
                            color: ctx.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: ctx.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pendant SIM Phone Number (for direct calling):',
                    style: TextStyle(color: ctx.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: pendantPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '+254740034499',
                      hintStyle: TextStyle(color: ctx.textMuted),
                      filled: true,
                      fillColor: ctx.inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: ctx.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: ctx.cardBorder),
                      ),
                      prefixIcon: const Icon(Icons.sim_card_outlined, color: AppColors.primary, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Parent / Guardian Phone Number (called when child holds pendant 3s):',
                    style: TextStyle(color: ctx.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: guardianPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: ctx.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '+254740034499',
                      hintStyle: TextStyle(color: ctx.textMuted),
                      filled: true,
                      fillColor: ctx.inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: ctx.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: ctx.cardBorder),
                      ),
                      prefixIcon: const Icon(Icons.supervisor_account_rounded, color: AppColors.success, size: 20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await controller.updatePendantPhoneConfig(
                          pendantSim: pendantPhoneCtrl.text,
                          guardianNumber: guardianPhoneCtrl.text,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Pendant & Guardian phone numbers synced!'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                      label: const Text(
                        'Save & Sync to Pendant',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final controller = context.watch<WearableController>();
    final isConnected = controller.isBleConnected || controller.pairedDevice != null;
    final isChildMode = controller.isChildMode;
    final deviceTitle = controller.pairedDevice?.deviceName.isNotEmpty == true
        ? controller.pairedDevice!.deviceName
        : 'SafeLink Pendant #JK001';

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Pendant',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              context.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: context.textPrimary,
              size: 21,
            ),
            onPressed: () => themeController.toggleDarkMode(),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: context.textPrimary, size: 22),
            tooltip: 'Pendant Phone & Guardian Settings',
            onPressed: () => _showPhoneSettingsSheet(context, controller),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. HERO PENDANT IMAGE WITH "CONNECTED" OVERLAY
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Image.asset(
                      'assets/images/pendant_device.jpg',
                      height: (MediaQuery.of(context).size.height * 0.22).clamp(140.0, 180.0),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 180,
                        color: context.surfaceBg,
                        child: Center(
                          child: Icon(Icons.watch_rounded, size: 64, color: context.textSecondary),
                        ),
                      ),
                    ),
                    Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        isConnected ? 'CONNECTED' : 'READY TO PAIR',
                        style: TextStyle(
                          color: isConnected ? const Color(0xFF2ECC71) : Colors.amberAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. CONNECTION STATUS CARD
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: context.isDarkMode
                          ? Colors.black.withValues(alpha: 0.25)
                          : AppColors.cardShadow,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: isConnected ? AppColors.success : Colors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'Connected' : 'Standby',
                          style: TextStyle(
                            color: isConnected ? AppColors.success : Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: isChildMode
                                ? const Color(0xFF8E44AD).withValues(alpha: 0.16)
                                : AppColors.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isChildMode ? const Color(0xFF8E44AD) : AppColors.primary,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isChildMode ? Icons.child_care_rounded : Icons.person_rounded,
                                size: 13,
                                color: isChildMode ? const Color(0xFF8E44AD) : AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isChildMode ? 'Child Mode' : 'Adult Mode',
                                style: TextStyle(
                                  color: isChildMode ? const Color(0xFF8E44AD) : AppColors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deviceTitle,
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bluetooth signal',
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _buildSignalBars(context, controller.signalBars, isConnected),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            if (controller.isBleConnected) {
                              await controller.unpairDevice();
                            } else {
                              await controller.startScan();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: context.inputBg,
                            foregroundColor: context.textPrimary,
                            side: BorderSide(color: context.cardBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              controller.isScanning
                                  ? 'Scanning...'
                                  : (controller.isBleConnected ? 'Disconnect' : 'Connect'),
                              maxLines: 1,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!controller.isHardwareGattLinked) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: controller.isScanning ? null : () => controller.startScan(),
                          icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                          label: Text(
                            controller.isScanning
                                ? 'Scanning for SafeGuard ESP32...'
                                : 'Scan & Link Live ESP32 Hardware (BLE)',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                    if (controller.discoveredDevices.isNotEmpty && !controller.isHardwareGattLinked) ...[
                      const SizedBox(height: 6),
                      ...controller.discoveredDevices.map(
                        (d) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bluetooth, color: AppColors.primary, size: 20),
                          title: Text(
                            d.platformName.isNotEmpty ? d.platformName : 'SafeGuard Pendant',
                            style: TextStyle(color: context.textPrimary, fontSize: 13),
                          ),
                          subtitle: Text(
                            d.remoteId.str,
                            style: TextStyle(color: context.textSecondary, fontSize: 11),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => controller.pairDevice(d),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text(
                              'Pair',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 3. TOUCH SENSITIVITY & CANCELLATION WINDOW SLIDERS
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Touch sensitivity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              isChildMode
                                  ? 'Disabled (Child Mode)'
                                  : '${controller.touchSensitivitySeconds.round()} seconds',
                              style: TextStyle(
                                color: isChildMode ? AppColors.warning : AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: isChildMode ? context.textMuted : AppColors.primary,
                        inactiveTrackColor: context.inputBg,
                        thumbColor: AppColors.primary,
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: Slider(
                        value: controller.touchSensitivitySeconds,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        onChanged: isChildMode
                            ? null
                            : (val) => controller.setTouchSensitivitySeconds(val),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('1s', style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
                          Text('10s', style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Cancellation window',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${controller.cancellationWindowSeconds.round()} seconds',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: context.inputBg,
                        thumbColor: AppColors.primary,
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: Slider(
                        value: controller.cancellationWindowSeconds,
                        min: 5,
                        max: 30,
                        divisions: 25,
                        onChanged: (val) => controller.setCancellationWindowSeconds(val),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('5s', style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
                          Text('30s', style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 5. WEARER MODE & PARENTAL CONTROL CARD (Adult vs Child Mode)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isChildMode
                        ? const Color(0xFF8E44AD).withValues(alpha: 0.5)
                        : context.cardBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isChildMode ? Icons.family_restroom_rounded : Icons.verified_user_rounded,
                          color: isChildMode ? const Color(0xFF8E44AD) : AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Wearer Mode & Parental Control',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isChildMode
                          ? 'Child Mode: Touch SOS on pendant is disabled to prevent accidental triggers. Holding pendant 3s calls parent. Parents can Locate & Call below.'
                          : 'Adult Mode: Wearer can trigger SOS via pendant touch sensor AND control the pendant from the phone app.',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => controller.setOwnerMode(PendantOwnerMode.adult),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: !isChildMode ? AppColors.primary : context.inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isChildMode ? AppColors.primary : context.cardBorder,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.person_rounded,
                                    color: !isChildMode ? Colors.white : context.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Adult Mode',
                                    style: TextStyle(
                                      color: !isChildMode ? Colors.white : context.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Touch SOS + App',
                                    style: TextStyle(
                                      color: !isChildMode ? Colors.white70 : context.textSecondary,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => controller.setOwnerMode(PendantOwnerMode.child),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: isChildMode ? const Color(0xFF8E44AD) : context.inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isChildMode ? const Color(0xFF8E44AD) : context.cardBorder,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.child_care_rounded,
                                    color: isChildMode ? Colors.white : context.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Child Mode',
                                    style: TextStyle(
                                      color: isChildMode ? Colors.white : context.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Parent Controlled',
                                    style: TextStyle(
                                      color: isChildMode ? Colors.white70 : context.textSecondary,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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

              const SizedBox(height: 12),

              // 6. REMOTE PENDANT CONTROL PANEL
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isChildMode
                                ? 'Parent Remote Monitor & Control'
                                : 'Remote Pendant Controls',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (controller.lastCommandFeedback != null)
                          const Icon(Icons.check_circle, color: AppColors.success, size: 17),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isChildMode
                          ? 'Monitor your child anytime: activate live GPS locate, call the pendant, or request a listen-in callback.'
                          : 'Control your pendant directly from your phone via Bluetooth & GSM.',
                      style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                    ),
                    if (controller.lastCommandFeedback != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: context.inputBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.primary, size: 15),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                controller.lastCommandFeedback!,
                                style: TextStyle(color: context.textPrimary, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (controller.pendantLat != null && controller.pendantLng != null) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => Navigator.pushNamed(context, '/map'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: AppColors.success, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Live Pendant Location Fix',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '${controller.pendantLat!.toStringAsFixed(5)}, ${controller.pendantLng!.toStringAsFixed(5)}',
                                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                'Map →',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildControlActionButton(
                            context: context,
                            icon: Icons.my_location_rounded,
                            label: controller.isLocatingPendant ? 'Locating...' : 'Activate Locate',
                            subtitle: 'Live GPS fix',
                            color: AppColors.success,
                            onTap: () => controller.locatePendantNow(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildControlActionButton(
                            context: context,
                            icon: Icons.phone_in_talk_rounded,
                            label: 'Call Pendant',
                            subtitle: 'Dial SIM voice',
                            color: AppColors.primary,
                            onTap: () => controller.callPendantDirectly(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildControlActionButton(
                            context: context,
                            icon: Icons.hearing_rounded,
                            label: 'Call-Back',
                            subtitle: 'Listen-in audio',
                            color: const Color(0xFF8E44AD),
                            onTap: () => controller.requestPendantCallBack(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildControlActionButton(
                            context: context,
                            icon: Icons.light_mode_rounded,
                            label: 'Blink ESP32 LED',
                            subtitle: 'Blinks GPIO8 + Serial',
                            color: AppColors.warning,
                            onTap: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('💡 Sending Blink command to ESP32 LED (GPIO8)...'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              final sent = await controller.findPendantLedStrobe();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(sent
                                        ? '✅ ESP32 LED (GPIO8) is blinking!'
                                        : '⚠️ Pendant not connected over BLE. Turn on Bluetooth & bring pendant close.'),
                                    backgroundColor: sent ? AppColors.success : AppColors.warning,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🚨 Triggering ESP32 Pendant SOS over BLE...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          await controller.triggerRemotePendantSos();
                          if (context.mounted) {
                            context.read<EmergencyController>().trigger(TriggerMethod.pendantTouch);
                            Navigator.pushNamed(context, '/emergency');
                          }
                        },
                        icon: const Icon(Icons.sos_rounded, color: AppColors.sosRed, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isChildMode
                                ? 'Trigger ESP32 & App SOS for Child'
                                : 'Trigger ESP32 Pendant & App SOS Now',
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.sosRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.sosRed),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignalBars(BuildContext context, int activeBars, bool isConnected) {
    final heights = [7.0, 11.0, 15.0, 19.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final active = isConnected && index < activeBars;
        return Container(
          margin: const EdgeInsets.only(right: 4),
          width: 4.5,
          height: heights[index],
          decoration: BoxDecoration(
            color: active ? AppColors.success : context.cardBorder,
            borderRadius: BorderRadius.circular(2.5),
          ),
        );
      }),
    );
  }

  Widget _buildControlActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: context.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
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
}
