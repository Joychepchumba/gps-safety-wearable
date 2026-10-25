import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../di/service_locator.dart';
import 'location_service.dart';

class BleService {
  final StreamController<bool> _pendantDetectedController = StreamController<bool>.broadcast();
  final StreamController<bool> _pendantAlertController = StreamController<bool>.broadcast();
  StreamSubscription? _scanSub;
  BluetoothDevice? _connectedDevice;

  SupabaseClient get _client => Supabase.instance.client;
  
  bool get isScanning => FlutterBluePlus.isScanningNow;

  Stream<bool> get pendantDetected => _pendantDetectedController.stream;
  Stream<bool> get pendantAlertStream => _pendantAlertController.stream;

  Future<void> startScan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == 'SafeGuard' || 
            r.advertisementData.serviceUuids.any((uuid) => uuid.toString().toLowerCase() == AppConstants.bleServiceUUID)) {
          _pendantDetectedController.add(true);
        }
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
  }

  Future<void> pairDevice(BluetoothDevice device, String userId) async {
    await device.connect(license: License.nonprofit);
    _connectedDevice = device;
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString().toLowerCase() == AppConstants.bleServiceUUID) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.uuid.toString().toLowerCase() == AppConstants.bleAlertCharUUID ||
              c.uuid.toString().toLowerCase().contains(AppConstants.bleAlertCharUUID)) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((value) {
              if (value.isNotEmpty && value[0] == 1) {
                _pendantAlertController.add(true);
              }
            });
          }
          if (c.uuid.toString().toLowerCase() == AppConstants.bleConfigCharUUID ||
              c.uuid.toString().toLowerCase().contains(AppConstants.bleConfigCharUUID)) {
            try {
              final locService = sl<LocationService>();
              final pos = await locService.getCurrentPosition();
              if (pos != null) {
                await c.write('LOC:${pos.latitude},${pos.longitude}'.codeUnits);
              }
            } catch (_) {}
          }
        }
      }
    }
    
    await _client.from('wearable_devices').upsert({
      'user_id': userId,
      'device_mac': device.remoteId.str,
      'device_name': device.platformName,
      'paired_at': DateTime.now().toIso8601String(),
      'is_active': true,
    });
  }

  Future<void> unpairDevice(String deviceMac) async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    await _client.from('wearable_devices').update({
      'is_active': false,
    }).eq('device_mac', deviceMac);
  }
}
