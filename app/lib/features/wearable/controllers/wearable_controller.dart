import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../models/wearable_device_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/di/service_locator.dart';

class WearableController extends ChangeNotifier {
  WearableDeviceModel? pairedDevice;
  bool isScanning = false;
  List<BluetoothDevice> discoveredDevices = [];

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final BleService _bleService = sl<BleService>();

  WearableController() {
    loadPairedDevice();
  }

  Future<void> loadPairedDevice() async {
    try {
      final user = _supabaseService.currentUser;
      if (user == null) return;

      final res = await _supabaseService.client
          .from('wearable_devices')
          .select()
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (res != null) {
        pairedDevice = WearableDeviceModel.fromJson(res);
      } else {
        pairedDevice = null;
      }
    } catch (e) {
      debugPrint('Error loading paired wearable: $e');
    }
    notifyListeners();
  }

  Future<void> startScan() async {
    isScanning = true;
    discoveredDevices = [];
    notifyListeners();

    try {
      await _bleService.startScan();
    } catch (_) {}

    isScanning = false;
    notifyListeners();
  }

  Future<void> pairDevice(BluetoothDevice device) async {
    final user = _supabaseService.currentUser;
    if (user == null) return;

    try {
      await _bleService.pairDevice(device, user.id);
      await loadPairedDevice();
    } catch (e) {
      debugPrint('Error pairing wearable: $e');
    }
    notifyListeners();
  }

  Future<void> unpairDevice() async {
    if (pairedDevice == null) return;
    try {
      await _bleService.unpairDevice(pairedDevice!.deviceMac);
      pairedDevice = null;
    } catch (e) {
      debugPrint('Error unpairing wearable: $e');
    }
    notifyListeners();
  }
}
