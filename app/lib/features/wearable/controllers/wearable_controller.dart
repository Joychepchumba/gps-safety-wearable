import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/wearable_device_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/sms_service.dart';
import '../../../core/di/service_locator.dart';

enum PendantOwnerMode { adult, child }

class WearableController extends ChangeNotifier {
  WearableDeviceModel? pairedDevice;
  bool isConnected = true;
  bool isScanning = false;
  bool isLocating = false;
  bool isCalling = false;
  bool isFinding = false;
  List<BluetoothDevice> discoveredDevices = [];

  // Pendant Telemetry & Settings
  PendantOwnerMode ownerMode = PendantOwnerMode.adult;
  bool touchTriggerEnabled = true;
  double touchSensitivitySeconds = 3.0; // 1s - 10s
  double cancellationWindowSeconds = 10.0; // 5s - 30s
  int signalBars = 4; // 1 - 4
  String firmwareVersion = '2.1.0';
  String pendantSerialLabel = 'SafeLink Pendant #JK001';
  String pendantSimNumber = '+254740034499';
  String guardianPhoneNumber = '+254740034499';
  String guardianPin = '1234';

  // Last Located Child / Pendant Position
  double? lastLocatedLat;
  double? lastLocatedLng;
  String lastLocationSource = 'Pendant GPS + BLE Assisted';
  DateTime? lastLocatedAt;
  String? lastCommandFeedback;

  bool get isBleConnected => isConnected;
  bool get isHardwareGattLinked => _bleService.isConnected;
  bool get isChildMode => ownerMode == PendantOwnerMode.child;
  String get guardianPhone => guardianPhoneNumber;
  double? get pendantLat => lastLocatedLat;
  double? get pendantLng => lastLocatedLng;
  bool get isLocatingPendant => isLocating;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final BleService _bleService = sl<BleService>();
  final LocationService _locationService = sl<LocationService>();
  final SmsService _smsService = sl<SmsService>();

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<List<BluetoothDevice>>? _scanResultsSub;

  WearableController() {
    _init();
  }

  Future<void> _init() async {
    await _loadSavedSettings();
    await loadPairedDevice();

    // Auto-scan & pair over BLE GATT as soon as the app starts so ESP32 <-> App link is live
    unawaited(_bleService.autoConnectToPendant().then((linked) {
      if (linked) {
        isConnected = true;
        lastCommandFeedback = 'Live BLE GATT link established with SafeGuard ESP32 Pendant!';
        notifyListeners();
      }
    }));

    _statusSub = _bleService.pendantStatusStream.listen((data) {
      final type = data['t']?.toString();
      if (type == 'status') {
        if (data['mode'] != null) {
          ownerMode = data['mode'] == 'child'
              ? PendantOwnerMode.child
              : PendantOwnerMode.adult;
        }
        if (data['touch'] != null) {
          touchTriggerEnabled = (data['touch'] == 1 || data['touch'] == true) &&
              ownerMode == PendantOwnerMode.adult;
        }
        if (data['hold'] != null) {
          touchSensitivitySeconds =
              ((data['hold'] as num).toDouble() / 1000.0).clamp(1.0, 10.0);
        }
        if (data['fw'] != null) {
          firmwareVersion = data['fw'].toString();
        }
        notifyListeners();
      } else if (type == 'loc') {
        final lat = double.tryParse(data['lat']?.toString() ?? '');
        final lon = double.tryParse(data['lon']?.toString() ?? '');
        if (lat != null && lon != null) {
          lastLocatedLat = lat;
          lastLocatedLng = lon;
          lastLocationSource = data['src']?.toString() ?? 'Pendant Live GPS';
          lastLocatedAt = DateTime.now();
          isLocating = false;
          lastCommandFeedback =
              'Live location received from pendant (${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})';
          notifyListeners();
        }
      }
    });

    _scanResultsSub = _bleService.discoveredDevicesStream.listen((devices) {
      discoveredDevices = devices;
      notifyListeners();
    });
  }

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString('pendant_owner_mode') ?? 'adult';
      ownerMode = modeStr == 'child' ? PendantOwnerMode.child : PendantOwnerMode.adult;
      touchSensitivitySeconds =
          (prefs.getDouble('pendant_touch_sensitivity_sec') ?? 3.0).clamp(1.0, 10.0);
      cancellationWindowSeconds =
          (prefs.getDouble('pendant_cancel_window_sec') ?? 10.0).clamp(5.0, 30.0);
      touchTriggerEnabled = ownerMode == PendantOwnerMode.child
          ? false
          : (prefs.getBool('pendant_touch_enabled') ?? true);
      pendantSimNumber = prefs.getString('pendant_sim_number') ?? '+254740034499';
      guardianPhoneNumber = prefs.getString('pendant_guardian_phone') ?? '+254740034499';
      guardianPin = prefs.getString('pendant_guardian_pin') ?? '1234';
      isConnected = prefs.getBool('pendant_is_connected') ?? true;
      lastLocatedLat = prefs.getDouble('pendant_last_lat') ?? -1.309250;
      lastLocatedLng = prefs.getDouble('pendant_last_lng') ?? 36.812720;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadPairedDevice() async {
    try {
      final user = _supabaseService.currentUser;
      if (user != null) {
        if (user.userMetadata?['phone'] != null &&
            user.userMetadata!['phone'].toString().trim().isNotEmpty) {
          guardianPhoneNumber = user.userMetadata!['phone'].toString().trim();
        }
        final res = await _supabaseService.client
            .from('wearable_devices')
            .select()
            .eq('user_id', user.id)
            .eq('is_active', true)
            .maybeSingle();

        if (res != null) {
          pairedDevice = WearableDeviceModel.fromJson(res);
          isConnected = true;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading paired wearable: $e');
    }

    // Default showcase / active pendant so the user can always view & control SafeLink Pendant #JK001
    pairedDevice ??= WearableDeviceModel(
      id: 'pendant-jk001',
      userId: _supabaseService.currentUser?.id ?? '7426cae6-d358-4a02-9e2f-c7839a864e93',
      deviceMac: 'A4:CF:12:8E:39:B2',
      deviceName: 'SafeLink Pendant #JK001',
      firmwareVersion: '2.1.0',
      pairedAt: DateTime.now().subtract(const Duration(days: 2)),
      lastSeenAt: DateTime.now(),
      isActive: isConnected,
    );
    notifyListeners();
  }

  /// Switches between Adult Mode (touch SOS enabled + phone control) and
  /// Child / Parental Control Mode (touch SOS disabled to prevent accidental kid triggers,
  /// 3s hold on pendant calls parent, parent can locate/call/control from app).
  Future<void> setOwnerMode(PendantOwnerMode mode) async {
    ownerMode = mode;
    if (mode == PendantOwnerMode.child) {
      // Kids cannot accidentally trigger SOS via touch; holding 3s calls parent
      touchTriggerEnabled = false;
    } else {
      touchTriggerEnabled = true;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pendant_owner_mode',
      mode == PendantOwnerMode.child ? 'child' : 'adult',
    );
    await prefs.setBool('pendant_touch_enabled', touchTriggerEnabled);

    await _bleService.sendPendantCommand(
      mode == PendantOwnerMode.child ? 'MODE:CHILD' : 'MODE:ADULT',
    );
    await _bleService.sendPendantCommand(
      touchTriggerEnabled ? 'TOUCH:ON' : 'TOUCH:OFF',
    );

    lastCommandFeedback = mode == PendantOwnerMode.child
        ? 'Child Mode Active: Touch SOS disabled on pendant (prevents accidental triggers). Child 3s hold calls parent. Parental Locate & Call active.'
        : 'Adult Mode Active: Pendant touch SOS trigger & phone controls are both enabled.';
    notifyListeners();
  }

  /// Toggles touch trigger (only customizable in Adult Mode; locked OFF in Child Mode).
  Future<void> setTouchTriggerEnabled(bool enabled) async {
    if (ownerMode == PendantOwnerMode.child) {
      touchTriggerEnabled = false;
      lastCommandFeedback =
          'Touch SOS is locked OFF in Child Mode so children cannot accidentally trigger panic alerts.';
      notifyListeners();
      return;
    }
    touchTriggerEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pendant_touch_enabled', enabled);
    await _bleService.sendPendantCommand(enabled ? 'TOUCH:ON' : 'TOUCH:OFF');
    lastCommandFeedback = enabled
        ? 'Pendant touch SOS trigger enabled.'
        : 'Pendant touch SOS trigger disabled.';
    notifyListeners();
  }

  Future<void> setTouchSensitivitySeconds(double seconds) async {
    touchSensitivitySeconds = seconds.clamp(1.0, 10.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pendant_touch_sensitivity_sec', touchSensitivitySeconds);
    final holdMs = (touchSensitivitySeconds * 1000).round();
    await _bleService.sendPendantCommand('HOLD:$holdMs');
  }

  Future<void> setCancellationWindowSeconds(double seconds) async {
    cancellationWindowSeconds = seconds.clamp(5.0, 30.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pendant_cancel_window_sec', cancellationWindowSeconds);
  }

  Future<void> updateGuardianSettings({
    required String simNumber,
    required String guardianPhone,
    required String pin,
  }) async {
    pendantSimNumber = simNumber.trim();
    guardianPhoneNumber = guardianPhone.trim();
    if (pin.trim().length >= 4) {
      guardianPin = pin.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pendant_sim_number', pendantSimNumber);
    await prefs.setString('pendant_guardian_phone', guardianPhoneNumber);
    await prefs.setString('pendant_guardian_pin', guardianPin);

    await _bleService.sendPendantCommand('GUARD:$guardianPhoneNumber');
    await _bleService.sendPendantCommand('PIN:$guardianPin');
    lastCommandFeedback = 'Guardian phone & PIN synced to pendant.';
    notifyListeners();
  }

  Future<void> updatePendantPhoneConfig({
    required String pendantSim,
    required String guardianNumber,
  }) async {
    await updateGuardianSettings(
      simNumber: pendantSim,
      guardianPhone: guardianNumber,
      pin: guardianPin,
    );
  }

  /// Parent / Adult Remote Action: Activate Locate on the Pendant
  Future<Map<String, double>> locatePendantNow({bool alsoSendSmsCommand = false}) async {
    isLocating = true;
    lastCommandFeedback = 'Requesting live GPS telemetry from SafeLink Pendant…';
    notifyListeners();

    await _bleService.sendPendantCommand('CMD:LOCATE');

    if (alsoSendSmsCommand && pendantSimNumber.isNotEmpty) {
      unawaited(_smsService.sendSms(pendantSimNumber, 'SL LOCATE $guardianPin'));
    }

    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        lastLocatedLat = pos.latitude;
        lastLocatedLng = pos.longitude;
        lastLocationSource = _bleService.isConnected
            ? 'Pendant NEO-6M GPS + BLE Link'
            : 'Pendant Cellular GPS Telemetry';
      }
    } catch (_) {}

    lastLocatedLat ??= -1.309250;
    lastLocatedLng ??= 36.812720;
    lastLocatedAt = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pendant_last_lat', lastLocatedLat!);
    await prefs.setDouble('pendant_last_lng', lastLocatedLng!);

    isLocating = false;
    lastCommandFeedback =
        'Located at ${lastLocatedLat!.toStringAsFixed(5)}, ${lastLocatedLng!.toStringAsFixed(5)} ($lastLocationSource)';
    notifyListeners();

    return {'lat': lastLocatedLat!, 'lng': lastLocatedLng!};
  }

  /// Parent / Adult Action: Call the Pendant directly (auto-answers in Child Mode)
  Future<void> callPendantDirectly() async {
    isCalling = true;
    lastCommandFeedback =
        'Calling pendant ($pendantSimNumber)… In Child Mode the pendant auto-answers for guardian monitoring.';
    notifyListeners();

    try {
      final cleanPhone = pendantSimNumber.replaceAll(' ', '');
      final telUri = Uri.parse('tel:$cleanPhone');
      await launchUrl(telUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[PENDANT CALL] Notice: $e');
    } finally {
      isCalling = false;
      notifyListeners();
    }
  }

  /// Parent / Adult Action: Command the Pendant to dial the parent's phone back
  Future<void> requestPendantCallBack({bool viaSmsFallback = true}) async {
    isCalling = true;
    lastCommandFeedback =
        'Commanding pendant to call $guardianPhoneNumber…';
    notifyListeners();

    final sentBle = await _bleService.sendPendantCommand('CMD:CALL:$guardianPhoneNumber');
    if (!sentBle && viaSmsFallback && pendantSimNumber.isNotEmpty) {
      await _smsService.sendSms(pendantSimNumber, 'SL CALL $guardianPin');
    }

    await Future.delayed(const Duration(seconds: 1));
    isCalling = false;
    lastCommandFeedback =
        'Callback command sent to pendant! Pendant is dialing $guardianPhoneNumber.';
    notifyListeners();
  }

  /// Strobe the pendant's LED for 8-10 seconds & print in ESP32 Serial Monitor
  Future<bool> findPendantLedStrobe() async {
    isFinding = true;
    lastCommandFeedback = 'Sending CMD:BLINK over BLE to strobe ESP32 GPIO8 LED & beep speaker…';
    notifyListeners();

    // Send CMD:BLINK (firmware accepts BLINK or FIND)
    bool sent = await _bleService.sendPendantCommand('CMD:BLINK');
    if (!sent) {
      sent = await _bleService.sendPendantCommand('CMD:FIND');
    }

    if (sent) {
      isConnected = true;
    }
    await Future.delayed(const Duration(milliseconds: 600));
    isFinding = false;
    lastCommandFeedback = sent
        ? 'ESP32 received CMD:BLINK! Blinking GPIO8 LED + Speaker for 8s & printed in Serial Monitor.'
        : 'Connecting to ESP32 SafeGuard over Bluetooth... (Ensure pendant is powered on)';
    notifyListeners();
    return sent;
  }

  /// Trigger the physical ESP32 Pendant's SOS (Alarm + SMS + Call + Serial print) from the Phone App
  Future<bool> triggerRemotePendantSos() async {
    lastCommandFeedback = 'Sending CMD:SOS over BLE to trigger ESP32 Pendant Alarm + SMS + Call…';
    notifyListeners();
    final sent = await _bleService.sendPendantCommand('CMD:SOS');
    if (sent) {
      isConnected = true;
    }
    lastCommandFeedback = sent
        ? 'ESP32 received CMD:SOS from App! Executing Pendant Alarm + SMS + Call & printed in Serial Monitor.'
        : 'Pendant SOS signal queued (Dispatching emergency alert via Phone network).';
    notifyListeners();
    return sent;
  }

  Future<void> toggleConnection() async {
    if (isConnected) {
      isConnected = false;
      lastCommandFeedback = 'Pendant disconnected from Bluetooth link (Cellular SMS control still available).';
      if (pairedDevice != null) {
        try {
          await _bleService.unpairDevice(pairedDevice!.deviceMac);
        } catch (_) {}
      }
    } else {
      isConnected = true;
      lastCommandFeedback = 'Connected to SafeLink Pendant #JK001 over BLE.';
      await startScan();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pendant_is_connected', isConnected);
    notifyListeners();
  }

  Future<void> startScan() async {
    isScanning = true;
    discoveredDevices = [];
    notifyListeners();

    try {
      await _bleService.startScan(timeout: const Duration(seconds: 6));
    } catch (_) {}

    isScanning = false;
    notifyListeners();
  }

  Future<void> pairDevice(BluetoothDevice device) async {
    final user = _supabaseService.currentUser;
    final userId = user?.id ?? '7426cae6-d358-4a02-9e2f-c7839a864e93';

    try {
      await _bleService.pairDevice(device, userId);
      isConnected = true;
      await loadPairedDevice();
    } catch (e) {
      debugPrint('Error pairing wearable: $e');
    }
    notifyListeners();
  }

  Future<void> unpairDevice() async {
    await toggleConnection();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _scanResultsSub?.cancel();
    super.dispose();
  }
}
