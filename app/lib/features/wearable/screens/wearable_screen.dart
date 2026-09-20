import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/wearable_device_model.dart';
import '../controllers/wearable_controller.dart';

class WearableScreen extends StatelessWidget {
  const WearableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WearableController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Safety Pendant', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: controller.pairedDevice != null
              ? _buildPairedView(controller.pairedDevice!, controller)
              : _buildUnpairedView(controller),
        ),
      ),
    );
  }

  Widget _buildPairedView(WearableDeviceModel device, WearableController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.watch, size: 90, color: AppColors.accent),
        const SizedBox(height: 20),
        Text(
          device.deviceName.isNotEmpty ? device.deviceName : 'SafeGuard Pendant',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 28),
        _buildInfoRow('MAC Address', device.deviceMac),
        _buildInfoRow('Firmware Version', device.firmwareVersion ?? '1.0.0'),
        _buildInfoRow('Status', device.isActive ? 'Active' : 'Inactive'),
        _buildInfoRow('Last Seen', 'Active now'),
        const Spacer(),
        OutlinedButton(
          onPressed: () => controller.unpairDevice(),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Unpair Device', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildUnpairedView(WearableController controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isScanning)
          const Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2.5,
              ),
            ),
          )
        else
          const Icon(Icons.bluetooth_searching, size: 90, color: AppColors.textSecondary),
        const SizedBox(height: 24),
        Text(
          controller.isScanning ? 'Scanning for SafeGuard Pendant...' : 'No Pendant Connected',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Make sure your pendant is turned on and in Bluetooth range.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 32),
        if (!controller.isScanning && controller.discoveredDevices.isEmpty)
          ElevatedButton(
            onPressed: () => controller.startScan(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Scan for Pendant',
              style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        if (controller.discoveredDevices.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: controller.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = controller.discoveredDevices[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth, color: AppColors.accent),
                  title: Text(device.platformName.isNotEmpty ? device.platformName : 'SafeGuard Device', style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(device.remoteId.str, style: const TextStyle(color: AppColors.textSecondary)),
                  trailing: ElevatedButton(
                    onPressed: () => controller.pairDevice(device),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                    child: const Text('Pair', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
