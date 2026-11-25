import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../di/service_locator.dart';
import 'location_service.dart';

class PendantAlertEvent {
  final int code;
  final String reason;
  final DateTime timestamp;

  PendantAlertEvent({
    required this.code,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isChildCallRequest => code == 0x10;
  bool get isCancel => code == 0x00;
  bool get isEmergencySos => code == 0x01 || code == 0x02 || code == 0x03;
}

class BleDistressBeacon {
  final String id;
  final String deviceMac;
  final String sourceType; // 'pendant_ble' or 'phone_ble'
  final double latitude;
  final double longitude;
  final String userTagHex;
  final int rssi;
  final double estimatedDistanceMeters;
  final DateTime detectedAt;
  final DateTime firstDetectedAt;
  final String? resolvedUserName;
  final String? resolvedPhone;

  BleDistressBeacon({
    required this.id,
    required this.deviceMac,
    required this.sourceType,
    required this.latitude,
    required this.longitude,
    required this.userTagHex,
    required this.rssi,
    required this.estimatedDistanceMeters,
    required this.detectedAt,
    DateTime? firstDetectedAt,
    this.resolvedUserName,
    this.resolvedPhone,
  }) : firstDetectedAt = firstDetectedAt ?? detectedAt;

  Duration get broadcastDuration => DateTime.now().difference(firstDetectedAt);

  String get broadcastDurationFormatted {
    final d = broadcastDuration;
    if (d.inSeconds < 60) {
      return '${d.inSeconds}s';
    } else if (d.inMinutes < 60) {
      final secs = d.inSeconds % 60;
      return '${d.inMinutes}m ${secs}s';
    } else {
      final mins = d.inMinutes % 60;
      return '${d.inHours}h ${mins}m';
    }
  }

  BleDistressBeacon copyWith({
    String? resolvedUserName,
    String? resolvedPhone,
    int? rssi,
    double? estimatedDistanceMeters,
    double? latitude,
    double? longitude,
    DateTime? detectedAt,
    DateTime? firstDetectedAt,
  }) {
    return BleDistressBeacon(
      id: id,
      deviceMac: deviceMac,
      sourceType: sourceType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      userTagHex: userTagHex,
      rssi: rssi ?? this.rssi,
      estimatedDistanceMeters: estimatedDistanceMeters ?? this.estimatedDistanceMeters,
      detectedAt: detectedAt ?? this.detectedAt,
      firstDetectedAt: firstDetectedAt ?? this.firstDetectedAt,
      resolvedUserName: resolvedUserName ?? this.resolvedUserName,
      resolvedPhone: resolvedPhone ?? this.resolvedPhone,
    );
  }
}

class BleService {
  final StreamController<bool> _pendantDetectedController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _pendantAlertController =
      StreamController<bool>.broadcast();
  final StreamController<PendantAlertEvent> _pendantEventController =
      StreamController<PendantAlertEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _pendantStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<BluetoothDevice>> _discoveredDevicesController =
      StreamController<List<BluetoothDevice>>.broadcast();
  final StreamController<List<BleDistressBeacon>> _distressBeaconsController =
      StreamController<List<BleDistressBeacon>>.broadcast();

  StreamSubscription? _scanSub;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _configCharacteristic;
  bool _isConnectingPendant = false;
  DateTime? _lastPendantSosEmitAt;

  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  bool _isBroadcastingSosBeacon = false;
  bool get isBroadcastingSosBeacon => _isBroadcastingSosBeacon;

  final Map<String, BleDistressBeacon> _activeBeacons = {};
  List<BleDistressBeacon> get activeBeacons => _activeBeacons.values.toList();

  SupabaseClient get _client => Supabase.instance.client;

  bool get isScanning => FlutterBluePlus.isScanningNow;
  bool get isConnected => _connectedDevice != null && _connectedDevice!.isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  Stream<bool> get pendantDetected => _pendantDetectedController.stream;
  Stream<bool> get pendantAlertStream => _pendantAlertController.stream;
  Stream<PendantAlertEvent> get pendantEventStream => _pendantEventController.stream;
  Stream<Map<String, dynamic>> get pendantStatusStream => _pendantStatusController.stream;
  Stream<List<BluetoothDevice>> get discoveredDevicesStream =>
      _discoveredDevicesController.stream;
  Stream<List<BleDistressBeacon>> get distressBeaconsStream =>
      _distressBeaconsController.stream;

  Future<void> ensureBlePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();
    } catch (e) {
      debugPrint('[BLE] Permission request notice: $e');
    }
  }

  /// Estimate distance in meters from BLE RSSI using log-distance path loss model.
  static double estimateDistanceMeters(int rssi, {int txPowerAt1m = -59}) {
    if (rssi == 0) return 25.0;
    final ratio = (txPowerAt1m - rssi) / (10.0 * 2.2);
    final dist = pow(10.0, ratio).toDouble();
    return dist.clamp(0.5, 500.0);
  }

  /// Encodes a 15-byte SafeLink BLE SOS payload (`"SL"` + source + lat + lon + userTag).
  static Uint8List encodeSosPayload({
    required double latitude,
    required double longitude,
    required String userId,
    bool isPendant = false,
  }) {
    final bd = ByteData(15);
    // Magic 'S' (0x53), 'L' (0x4C)
    bd.setUint8(0, 0x53);
    bd.setUint8(1, 0x4C);
    // Source: 0x01 = Pendant, 0x02 = Phone
    bd.setUint8(2, isPendant ? 0x01 : 0x02);
    // Latitude * 1e6 int32 LE
    final latFixed = (latitude * 1000000).round();
    final lonFixed = (longitude * 1000000).round();
    bd.setInt32(3, latFixed, Endian.little);
    bd.setInt32(7, lonFixed, Endian.little);
    // First 8 hex chars of userId as uint32 LE
    final cleanHex = userId.replaceAll('-', '').padRight(8, '0').substring(0, 8);
    final userTag = int.tryParse(cleanHex, radix: 16) ?? 0x7426CAE6;
    bd.setUint32(11, userTag, Endian.little);
    return bd.buffer.asUint8List();
  }

  /// Decodes a 15-byte (or 17-byte with 0xFFFF prefix) SafeLink BLE SOS payload from manufacturer data.
  static BleDistressBeacon? decodeSosPayload({
    required List<int> bytes,
    required String deviceMac,
    required int rssi,
  }) {
    if (bytes.length < 15) return null;

    // Handle 17-byte raw payload where 2-byte company ID 0xFFFF is still prefixed
    List<int> cleanBytes = bytes;
    if (bytes.length >= 17 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xFF &&
        bytes[2] == 0x53 &&
        bytes[3] == 0x4C) {
      cleanBytes = bytes.sublist(2);
    }

    if (cleanBytes.length < 15) return null;
    if (cleanBytes[0] != 0x53 || cleanBytes[1] != 0x4C) return null;

    final bd = ByteData.sublistView(Uint8List.fromList(cleanBytes));
    final sourceByte = bd.getUint8(2);
    final latFixed = bd.getInt32(3, Endian.little);
    final lonFixed = bd.getInt32(7, Endian.little);
    final userTag = bd.getUint32(11, Endian.little);

    final lat = latFixed / 1000000.0;
    final lon = lonFixed / 1000000.0;
    final tagHex = userTag.toRadixString(16).padLeft(8, '0').toLowerCase();
    final dist = estimateDistanceMeters(rssi);

    return BleDistressBeacon(
      id: 'ble_${tagHex}_$deviceMac',
      deviceMac: deviceMac,
      sourceType: sourceByte == 0x01 ? 'pendant_ble' : 'phone_ble',
      latitude: lat,
      longitude: lon,
      userTagHex: tagHex,
      rssi: rssi,
      estimatedDistanceMeters: dist,
      detectedAt: DateTime.now(),
    );
  }

  /// Broadcasts this phone's SOS location over BLE so nearby Community Responders
  /// can detect the user in distress even without internet/cloud connectivity.
  Future<bool> startSosBeaconBroadcast({
    required double latitude,
    required double longitude,
    required String userId,
    bool isPendantTrigger = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) {
      return false;
    }
    try {
      await ensureBlePermissions();
      final payload = encodeSosPayload(
        latitude: latitude,
        longitude: longitude,
        userId: userId,
        isPendant: isPendantTrigger,
      );

      if (_isBroadcastingSosBeacon) {
        try {
          await _blePeripheral.stop();
        } catch (_) {}
      }

      // Keep BLE legacy advertisement strictly <= 31 bytes by advertising ONLY
      // the 2-byte manufacturerId + 15-byte SOS payload (19 bytes total with header)
      final advertiseData = AdvertiseDataCore(
        manufacturerId: AppConstants.bleSosManufacturerId,
        manufacturerData: payload,
      );

      await _blePeripheral.start(advertiseData: advertiseData);
      _isBroadcastingSosBeacon = true;
      debugPrint(
        '[BLE SOS BEACON] Broadcasting BLE distress beacon (${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)})',
      );
      return true;
    } catch (e) {
      debugPrint('[BLE SOS BEACON] Broadcast start notice: $e');
      return false;
    }
  }

  /// Stops broadcasting the phone BLE SOS beacon.
  Future<void> stopSosBeaconBroadcast() async {
    try {
      if (_isBroadcastingSosBeacon) {
        await _blePeripheral.stop();
      }
    } catch (e) {
      debugPrint('[BLE SOS BEACON] Stop notice: $e');
    } finally {
      _isBroadcastingSosBeacon = false;
    }
  }

  /// Starts BLE scanning for both SafeGuard pendants AND nearby BLE SOS distress beacons.
  Future<List<BluetoothDevice>> startScan({
    Duration timeout = const Duration(seconds: 12),
    bool forCommunityResponderRadar = false,
  }) async {
    await ensureBlePermissions();
    final List<BluetoothDevice> foundDevices = [];

    try {
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        bool beaconsUpdated = false;
        for (final ScanResult r in results) {
          final advName = r.advertisementData.advName;
          final platName = r.device.platformName;
          final devName = (advName.isNotEmpty ? advName : platName).toLowerCase();
          final hasService = r.advertisementData.serviceUuids.any(
            (uuid) => uuid.toString().toLowerCase().contains(AppConstants.bleServiceUUID),
          );

          // 1. Check for SafeGuard Pendant devices
          if (devName.contains('safeguard') ||
              devName.contains('safelink') ||
              hasService) {
            _pendantDetectedController.add(true);
            if (!foundDevices.any((d) => d.remoteId == r.device.remoteId)) {
              foundDevices.add(r.device);
              _discoveredDevicesController.add(List.unmodifiable(foundDevices));
            }
            // Auto-connect to SafeGuard ESP32 pendant over GATT when discovered
            if (!isConnected && !_isConnectingPendant) {
              _isConnectingPendant = true;
              final uid = _client.auth.currentUser?.id ??
                  '7426cae6-d358-4a02-9e2f-c7839a864e93';
              unawaited(
                pairDevice(r.device, uid).catchError((e) {
                  debugPrint('[BLE AUTO-CONNECT] Error pairing: $e');
                }).whenComplete(() {
                  _isConnectingPendant = false;
                }),
              );
            }
          }

          // 2. Check for BLE SOS Distress Beacon in Manufacturer Specific Data (0xFFFF)
          final msd = r.advertisementData.manufacturerData;
          for (final entry in msd.entries) {
            final bytes = entry.value;
            final beacon = decodeSosPayload(
              bytes: bytes,
              deviceMac: r.device.remoteId.str,
              rssi: r.rssi,
            );
            if (beacon != null) {
              final existing = _activeBeacons[beacon.userTagHex];
              final updatedBeacon = existing != null
                  ? beacon.copyWith(
                      firstDetectedAt: existing.firstDetectedAt,
                      resolvedUserName: existing.resolvedUserName ?? beacon.resolvedUserName,
                      resolvedPhone: existing.resolvedPhone ?? beacon.resolvedPhone,
                    )
                  : beacon;
              _activeBeacons[beacon.userTagHex] = updatedBeacon;
              beaconsUpdated = true;
              debugPrint(
                '🆘 [BLE RADAR] Distress beacon ${updatedBeacon.userTagHex} (${updatedBeacon.sourceType}) active for ${updatedBeacon.broadcastDurationFormatted} at ${updatedBeacon.latitude}, ${updatedBeacon.longitude} (~${updatedBeacon.estimatedDistanceMeters.toStringAsFixed(1)}m)',
              );
              // Ensure any pendant BLE SOS beacon also triggers the app's Emergency SOS listener
              if (beacon.sourceType == 'pendant_ble') {
                _emitDeduplicatedPendantSos(
                  code: 0x02,
                  reason: 'pendant_ble_beacon',
                );
              }
            }
          }
        }

        if (beaconsUpdated) {
          _distressBeaconsController.add(_activeBeacons.values.toList());
        }
      });

      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: forCommunityResponderRadar,
      );
    } catch (e) {
      debugPrint('[BLE SCAN] Notice: $e');
    }

    return foundDevices;
  }

  /// Injects a simulated BLE distress beacon (useful for testing/demo when only 1 phone is present).
  BleDistressBeacon simulateIncomingBleDistressBeacon({
    required double baseLat,
    required double baseLng,
    String sourceType = 'pendant_ble',
    String victimName = 'Guardian Pendant #JK001',
    String? victimPhone,
  }) {
    final beacon = BleDistressBeacon(
      id: 'ble_sim_${DateTime.now().millisecondsSinceEpoch}',
      deviceMac: 'A4:CF:12:8E:39:B2',
      sourceType: sourceType,
      latitude: baseLat + 0.00065,
      longitude: baseLng + 0.00055,
      userTagHex: '7426cae6',
      rssi: -64,
      estimatedDistanceMeters: 18.5,
      detectedAt: DateTime.now(),
      resolvedUserName: victimName,
      resolvedPhone: victimPhone ?? '+254740034499',
    );
    _activeBeacons[beacon.id] = beacon;
    _distressBeaconsController.add(_activeBeacons.values.toList());
    return beacon;
  }

  void clearBeacon(String idOrTag) {
    _activeBeacons.remove(idOrTag);
    _activeBeacons.removeWhere((k, v) => v.id == idOrTag || v.userTagHex == idOrTag);
    _distressBeaconsController.add(_activeBeacons.values.toList());
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void _emitDeduplicatedPendantSos({
    required int code,
    required String reason,
  }) {
    final now = DateTime.now();
    if (_lastPendantSosEmitAt != null &&
        now.difference(_lastPendantSosEmitAt!) < const Duration(seconds: 12)) {
      return;
    }
    _lastPendantSosEmitAt = now;
    _pendantAlertController.add(true);
    _pendantEventController.add(PendantAlertEvent(code: code, reason: reason));
  }

  /// Automatically scans for and connects to the SafeGuard ESP32 pendant if not yet connected.
  Future<bool> autoConnectToPendant({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (isConnected && _configCharacteristic != null) return true;

    // 1. Check system-connected Bluetooth devices first
    try {
      final sysDevices = FlutterBluePlus.connectedDevices;
      for (final d in sysDevices) {
        final name = d.platformName.toLowerCase();
        if (name.contains('safeguard') || name.contains('safelink')) {
          final uid = _client.auth.currentUser?.id ??
              '7426cae6-d358-4a02-9e2f-c7839a864e93';
          await pairDevice(d, uid);
          if (isConnected && _configCharacteristic != null) {
            debugPrint('[BLE AUTO-CONNECT] Connected via existing system connection: ${d.remoteId.str}');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE AUTO-CONNECT] Error checking system devices: $e');
    }

    // 2. Active BLE scan if not already paired
    final devices = await startScan(timeout: timeout);
    if (isConnected && _configCharacteristic != null) return true;
    if (devices.isNotEmpty) {
      final uid = _client.auth.currentUser?.id ??
          '7426cae6-d358-4a02-9e2f-c7839a864e93';
      try {
        await pairDevice(devices.first, uid);
        return isConnected && _configCharacteristic != null;
      } catch (e) {
        debugPrint('[BLE AUTO-CONNECT] Error pairing discovered device: $e');
      }
    }
    return isConnected && _configCharacteristic != null;
  }

  Future<void> pairDevice(BluetoothDevice device, String userId) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await device.connect(
      license: License.nonprofit,
      autoConnect: false,
      timeout: const Duration(seconds: 8),
    );
    _connectedDevice = device;
    final List<BluetoothService> services = await device.discoverServices();
    for (final BluetoothService service in services) {
      if (service.uuid.toString().toLowerCase().contains(AppConstants.bleServiceUUID)) {
        for (final BluetoothCharacteristic c in service.characteristics) {
          final charUuid = c.uuid.toString().toLowerCase();

          // 1. Alert characteristic (ffe1)
          if (charUuid.contains(AppConstants.bleAlertCharUUID)) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((value) async {
              if (value.isEmpty) return;
              final code = value[0];
              if (code == 0x01 || code == 0x02 || code == 0x03) {
                final reason = code == 0x02
                    ? 'pendant_voice'
                    : (code == 0x03 ? 'remote_guardian' : 'pendant_touch');
                _emitDeduplicatedPendantSos(code: code, reason: reason);

                // Also emit directly into the BLE distress beacon stream & re-broadcast
                try {
                  final locService = sl<LocationService>();
                  final pos = await locService.getCurrentPosition().timeout(
                        const Duration(seconds: 3),
                        onTimeout: () => null,
                      );
                  final lat = pos?.latitude ?? -1.2907850038543573;
                  final lon = pos?.longitude ?? 36.78176897301627;
                  final cleanHex = userId.replaceAll('-', '').padRight(8, '0').substring(0, 8).toLowerCase();
                  final beacon = BleDistressBeacon(
                    id: 'ble_${cleanHex}_${device.remoteId.str}',
                    deviceMac: device.remoteId.str,
                    sourceType: 'pendant_ble',
                    latitude: lat,
                    longitude: lon,
                    userTagHex: cleanHex,
                    rssi: -52,
                    estimatedDistanceMeters: 3.5,
                    detectedAt: DateTime.now(),
                    resolvedUserName: 'SafeGuard Pendant #JK001 ($reason)',
                  );
                  _activeBeacons[cleanHex] = beacon;
                  _distressBeaconsController.add(_activeBeacons.values.toList());
                  await startSosBeaconBroadcast(
                    latitude: lat,
                    longitude: lon,
                    userId: userId,
                    isPendantTrigger: true,
                  );
                } catch (_) {}
              } else if (code == 0x10) {
                // Child mode 3s hold -> Call Parent request
                _pendantEventController.add(
                  PendantAlertEvent(code: 0x10, reason: 'child_call_parent'),
                );
              } else if (code == 0x00) {
                _pendantEventController.add(
                  PendantAlertEvent(code: 0x00, reason: 'cancelled'),
                );
                stopSosBeaconBroadcast();
              }
            });
          }

          // 2. Config characteristic (ffe2)
          if (charUuid.contains(AppConstants.bleConfigCharUUID)) {
            _configCharacteristic = c;
            try {
              final locService = sl<LocationService>();
              final pos = await locService.getCurrentPosition();
              if (pos != null) {
                await c.write(utf8.encode('LOC:${pos.latitude},${pos.longitude}'));
              }
            } catch (_) {}
          }

          // 3. Status characteristic (ffe3)
          if (charUuid.contains(AppConstants.bleStatusCharUUID)) {
            try {
              await c.setNotifyValue(true);
              c.onValueReceived.listen((value) {
                if (value.isEmpty) return;
                try {
                  final jsonStr = utf8.decode(value, allowMalformed: true).trim();
                  if (jsonStr.startsWith('{')) {
                    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
                    _pendantStatusController.add(decoded);
                    if (decoded['sos'] == 1 || decoded['sos'] == true) {
                      _emitDeduplicatedPendantSos(
                        code: 0x02,
                        reason: decoded['reason']?.toString() ?? 'pendant_voice',
                      );
                    }
                  }
                } catch (_) {}
              });
            } catch (_) {}
          }
        }
      }
    }

    try {
      await _client.from('wearable_devices').upsert({
        'user_id': userId,
        'device_mac': device.remoteId.str,
        'device_name': device.platformName.isNotEmpty ? device.platformName : 'SafeLink Pendant #JK001',
        'paired_at': DateTime.now().toIso8601String(),
        'last_seen_at': DateTime.now().toIso8601String(),
        'is_active': true,
      });
    } catch (e) {
      debugPrint('[BLE PAIR] Supabase sync notice (non-fatal): $e');
    }
  }

  /// Sends a protocol v2.1 command to the connected SafeLink Pendant over BLE (`ffe2`).
  /// Examples: `MODE:CHILD`, `MODE:ADULT`, `TOUCH:OFF`, `TOUCH:ON`, `HOLD:3000`,
  /// `CMD:LOCATE`, `CMD:CALL:+254...`, `CMD:FIND`, `CMD:BLINK`, `CMD:SOS`, `CMD:CANCEL`, `CMD:STATUS`.
  Future<bool> sendPendantCommand(String command) async {
    try {
      if (_configCharacteristic == null || !isConnected) {
        debugPrint('[BLE CMD] Not yet GATT-connected; auto-scanning for SafeGuard ESP32...');
        await autoConnectToPendant(timeout: const Duration(seconds: 4));
      }
      if (_configCharacteristic != null && isConnected) {
        final bytes = utf8.encode(command);
        try {
          await _configCharacteristic!.write(bytes, withoutResponse: false);
        } catch (_) {
          await _configCharacteristic!.write(bytes, withoutResponse: true);
        }
        debugPrint('[BLE CMD] Sent to ESP32 pendant over GATT (ffe2): $command');
        return true;
      }
      debugPrint('[BLE CMD] Pendant not directly connected over GATT; command queued/simulated: $command');
      return false;
    } catch (e) {
      debugPrint('[BLE CMD] Failed sending "$command": $e');
      return false;
    }
  }

  Future<void> unpairDevice(String deviceMac) async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
      _configCharacteristic = null;
    }
    try {
      await _client.from('wearable_devices').update({
        'is_active': false,
      }).eq('device_mac', deviceMac);
    } catch (_) {}
  }
}
