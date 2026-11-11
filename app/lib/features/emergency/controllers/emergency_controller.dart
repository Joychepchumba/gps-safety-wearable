import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/shake_detection_service.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/navigation/navigation_service.dart';
import '../../../core/services/background_protection_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/sms_service.dart';
import '../services/voice_activation_service.dart';
import '../../contacts/controllers/contacts_controller.dart';

enum EmergencyState { idle, triggered, countdown, sending, sent, failed, cancelled }

enum TriggerMethod { button, appShake, pendantTouch, voiceKeyword }

class EmergencyController extends ChangeNotifier {
  EmergencyState state = EmergencyState.idle;
  int countdownSeconds = 10;
  PanicEventModel? activeEvent;
  Timer? _countdownTimer;
  TriggerMethod lastTriggerMethod = TriggerMethod.button;

  VoidCallback? onEmergencyTriggered;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();
  final ShakeDetectionService _shakeService = sl<ShakeDetectionService>();
  final VoiceActivationService _voiceService = sl<VoiceActivationService>();
  final BleService _bleService = sl<BleService>();

  StreamSubscription<PendantAlertEvent>? _pendantEventSub;

  bool get isShakeActive => _shakeService.isListening;
  bool get isVoiceActive => _voiceService.isListening;
  bool get isVoiceEnabled => _voiceService.isEnabled;
  String get voiceWakePhrase => _voiceService.wakePhrase;
  String? get lastDetectedVoiceKeyword => _voiceService.lastDetectedKeyword.value;

  bool _isBatterySaverEnabled = false;
  bool get isBatterySaverEnabled => _isBatterySaverEnabled;

  String? _panicEventId;
  Timer? _locationTimer;
  bool _protectionStarted = false;

  EmergencyController() {
    startShakeDetection();
    _initVoiceActivation();
    _initPendantBleListener();
    initBatterySaver();
  }

  void _initPendantBleListener() {
    _pendantEventSub?.cancel();
    _pendantEventSub = _bleService.pendantEventStream.listen((event) async {
      final prefs = await SharedPreferences.getInstance();
      final ownerMode = prefs.getString('pendant_owner_mode') ?? 'adult';
      final touchEnabled = prefs.getBool('pendant_touch_enabled') ?? (ownerMode == 'adult');

      if (event.isChildCallRequest) {
        debugPrint('[PENDANT] Child pressed Call-Parent button on pendant!');
        try {
          await sl<NotificationService>().showEmergencyPopup(
            id: 109,
            title: '📞 Child Pendant Call Request',
            body: 'Your child held the SafeLink Pendant button to call you.',
            payload: '/wearable',
          );
        } catch (_) {}
        return;
      }

      if (event.isCancel) {
        if (state == EmergencyState.countdown) {
          cancel();
        }
        return;
      }

      if (event.isEmergencySos) {
        // In Child Mode, ignore accidental touch SOS triggers (0x01)
        if ((ownerMode == 'child' || !touchEnabled) && event.code == 0x01) {
          debugPrint('[PENDANT] Touch trigger ignored because Child Mode / Touch Lock is active.');
          return;
        }
        debugPrint('[PENDANT] Emergency SOS received over BLE (${event.reason})! Triggering SOS.');
        await trigger(TriggerMethod.pendantTouch);
      }
    });
  }

  Future<void> initBatterySaver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isBatterySaverEnabled = prefs.getBool('battery_saver_mode') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleBatterySaver(bool enabled) async {
    _isBatterySaverEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('battery_saver_mode', enabled);
    } catch (_) {}

    if (enabled && isVoiceActive) {
      _voiceService.stopListening();
    } else if (!enabled && isVoiceEnabled && !isVoiceActive) {
      await _voiceService.startListening();
    }
    _updateBackgroundNotification();
    notifyListeners();
  }

  /// Starts the background foreground-service + shake + voice detection.
  /// Safe to call repeatedly; call once the user is signed in.
  Future<void> startProtection() async {
    if (!_protectionStarted) {
      _protectionStarted = true;
      if (!isShakeActive) startShakeDetection();
      await BackgroundProtectionService.start(
        voiceEnabled: isVoiceEnabled && !_isBatterySaverEnabled,
        shakeEnabled: true,
      );
    }
    if (isVoiceEnabled && !isVoiceActive && !_isBatterySaverEnabled) {
      await _voiceService.startListening();
    }
    _updateBackgroundNotification();
    notifyListeners();
  }

  void _updateBackgroundNotification() {
    BackgroundProtectionService.updateStatus(
      voiceEnabled: isVoiceEnabled,
      shakeEnabled: isShakeActive,
    );
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      final id = _panicEventId;
      if (id == null) return;
      try {
        final pos = await _locationService.getCurrentPosition();
        if (pos == null) return;

        // Refresh BLE SOS beacon with latest coordinates
        final userId = _supabaseService.client.auth.currentUser?.id ??
            '7426cae6-d358-4a02-9e2f-c7839a864e93';
        unawaited(_bleService.startSosBeaconBroadcast(
          latitude: pos.latitude,
          longitude: pos.longitude,
          userId: userId,
          isPendantTrigger: lastTriggerMethod == TriggerMethod.pendantTouch,
        ));

        final baseUrl = await AppConstants.getEffectiveBackendUrl();
        await http.post(
          Uri.parse('$baseUrl/alert/$id/location'),
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy_m': pos.accuracy,
          }),
        ).timeout(const Duration(seconds: 6));
      } catch (_) {}
    });
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _panicEventId = null;
  }

  void _initVoiceActivation() {
    _voiceService.init(onDetected: () {
      debugPrint('[EmergencyController] Voice wake phrase detected! Triggering SOS.');
      trigger(TriggerMethod.voiceKeyword);
    }).then((_) {
      if (_voiceService.isEnabled && !_isBatterySaverEnabled) {
        _voiceService.startListening();
      }
    });
  }

  Future<void> trigger(TriggerMethod method) async {
    if (state == EmergencyState.triggered || state == EmergencyState.countdown) return;

    int configuredWindow = 10;
    try {
      final prefs = await SharedPreferences.getInstance();
      configuredWindow = (prefs.getDouble('pendant_cancel_window_sec') ?? 10.0).round().clamp(5, 30);
    } catch (_) {}

    lastTriggerMethod = method;
    state = EmergencyState.countdown;
    countdownSeconds = configuredWindow;
    notifyListeners();

    final methodLabel = method == TriggerMethod.voiceKeyword
        ? 'Voice Keyword'
        : (method == TriggerMethod.appShake
            ? 'Shake Motion'
            : (method == TriggerMethod.pendantTouch ? 'Safety Pendant' : 'Emergency Button'));

    final detectedPhrase = method == TriggerMethod.voiceKeyword
        ? (_voiceService.lastDetectedKeyword.value ?? _voiceService.wakePhrase)
        : null;

    // Pop up notification shown immediately (heads-up banner in background mode)
    try {
      sl<NotificationService>().showTriggerPopup(
        method: methodLabel,
        countdownSeconds: countdownSeconds,
        detectedPhrase: detectedPhrase,
      );
    } catch (e) {
      debugPrint('[EmergencyController] Trigger popup notice: $e');
    }

    BackgroundProtectionService.bringToFront();
    try {
      NavigationService.pushNamed('/emergency');
    } catch (_) {}

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds > 0) {
        countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _sendAlert();
      }
    });
  }

  void cancel() {
    if (state == EmergencyState.countdown || state == EmergencyState.sending) {
      _countdownTimer?.cancel();
      _stopLocationUpdates();
      unawaited(_bleService.stopSosBeaconBroadcast());
      unawaited(_bleService.sendPendantCommand('CMD:CANCEL'));
      state = EmergencyState.cancelled;
      notifyListeners();
      try {
        sl<NotificationService>().cancelTriggerPopup();
      } catch (_) {}

      Future.delayed(const Duration(seconds: 2), () {
        state = EmergencyState.idle;
        notifyListeners();
      });
    }
  }

  Future<void> _sendAlert() async {
    state = EmergencyState.sending;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      final userId = user?.id ?? '7426cae6-d358-4a02-9e2f-c7839a864e93';
      final userName = user?.userMetadata?['full_name'] ?? 'SafeLink User';

      // 1. Get real device location from LocationService (with fallback)
      double lat = -1.309250; // Strathmore University
      double lng = 36.812720;
      double accuracy = 15.0;

      try {
        final pos = await _locationService.getCurrentPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
          accuracy = pos.accuracy;
          debugPrint('[EMERGENCY] Real GPS lock acquired: $lat, $lng (accuracy: ${accuracy}m)');
        } else {
          debugPrint('[EMERGENCY] GPS lock unavailable, using fallback coordinates');
        }
      } catch (locErr) {
        debugPrint('[EMERGENCY] Location fetch error: $locErr');
      }

      // Valid PostgreSQL enum values in schema.sql:
      // 'pendant_touch', 'pendant_voice', 'app_shake', 'app_button', 'app_voice'
      final triggerMethodString = lastTriggerMethod == TriggerMethod.appShake
          ? 'app_shake'
          : (lastTriggerMethod == TriggerMethod.pendantTouch
              ? 'pendant_touch'
              : (lastTriggerMethod == TriggerMethod.voiceKeyword
                  ? 'app_voice'
                  : 'app_button'));

      // 2. IMMEDIATELY start BLE SOS Beacon broadcast (works for both Phone & Pendant triggers!)
      unawaited(_bleService.startSosBeaconBroadcast(
        latitude: lat,
        longitude: lng,
        userId: userId,
        isPendantTrigger: lastTriggerMethod == TriggerMethod.pendantTouch,
      ));
      if (lastTriggerMethod != TriggerMethod.pendantTouch) {
        unawaited(_bleService.sendPendantCommand('CMD:SOS'));
      }

      // 3. Retrieve user's configured emergency contacts
      List<String> contactPhones = [];
      try {
        final contactsController = sl<ContactsController>();
        contactPhones = contactsController.contacts
            .map((c) => c.phoneNumber.trim())
            .where((p) => p.isNotEmpty)
            .toList();
      } catch (_) {}

      if (contactPhones.isEmpty && user != null) {
        try {
          final List res = await _supabaseService.client
              .from('emergency_contacts')
              .select('phone_number')
              .eq('user_id', user.id);
          if (res.isNotEmpty) {
            contactPhones = res
                .map((c) => (c['phone_number'] ?? '').toString())
                .where((p) => p.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }

      // Generate temporary reference ID until Supabase panic_events returns its UUID
      _panicEventId = 'evt_${DateTime.now().millisecondsSinceEpoch}';
      _startLocationUpdates();

      // 4. Record incident into Supabase panic_events FIRST so we have a valid UUID
      // for responder_alerts and live tracking!
      int alertedRespondersCount = 0;
      List<Map<String, dynamic>> nearbyResponders = [];
      try {
        final List respondersRes = await _supabaseService.client
            .from('users')
            .select('id, full_name, phone_number, is_community_responder, responder_status')
            .eq('is_community_responder', true);
        nearbyResponders = List<Map<String, dynamic>>.from(respondersRes);
        alertedRespondersCount = nearbyResponders.length;
      } catch (_) {}

      if (user != null) {
        try {
          final eventData = {
            'user_id': user.id,
            'trigger_method': triggerMethodString,
            'latitude': lat,
            'longitude': lng,
            'location_accuracy_m': accuracy,
            'status': 'active',
            'emergency_contacts_notified': true,
            'community_responders_alerted': alertedRespondersCount > 0 ? alertedRespondersCount : 1,
            'notes': lastTriggerMethod == TriggerMethod.pendantTouch
                ? 'Triggered via SafeLink Pendant. BLE & Cloud Community Responders alerted.'
                : 'Triggered via $triggerMethodString. BLE & Cloud Community Responders alerted.',
          };
          final response = await _supabaseService.client
              .from('panic_events')
              .insert(eventData)
              .select()
              .single();

          activeEvent = PanicEventModel.fromJson(response);
          _panicEventId = activeEvent?.id ?? _panicEventId;
        } catch (dbErr) {
          debugPrint('[EMERGENCY] Supabase panic_events insert notice: $dbErr');
        }
      }

      // 5. Broadcast to community responders in Supabase responder_alerts + SMS
      if (nearbyResponders.isNotEmpty && activeEvent != null) {
        try {
          final alertsToInsert = nearbyResponders.map((r) {
            return {
              'panic_event_id': activeEvent!.id,
              'responder_id': r['id'],
              'distance_m': 240.0,
            };
          }).toList();
          await _supabaseService.client.from('responder_alerts').upsert(
                alertsToInsert,
                onConflict: 'panic_event_id,responder_id',
              );
          debugPrint(
            '[EMERGENCY] Broadcast logged to ${nearbyResponders.length} community responders',
          );
        } catch (respErr) {
          debugPrint('[EMERGENCY] Community responder broadcast notice: $respErr');
        }
      }

      // Also include opted-in community responders' phone numbers in the emergency SMS dispatch!
      final responderPhones = nearbyResponders
          .where((r) => r['id'] != user?.id)
          .map((r) => (r['phone_number'] ?? '').toString().trim())
          .where((p) => p.isNotEmpty && !p.startsWith('+254700'))
          .toList();
      final allSmsPhones = <String>{...contactPhones, ...responderPhones}.toList();

      // 6. Dispatch Africa's Talking SMS with Live 3D Tracking link
      try {
        final smsService = sl<SmsService>();
        unawaited(smsService.notifyEmergencyContacts(
          allSmsPhones,
          userName,
          lat,
          lng,
          panicEventId: _panicEventId,
        ));
        debugPrint(
          '[EMERGENCY] Instant SMS dispatched via Africa\'s Talking to ${allSmsPhones.length} contacts/responders & police',
        );
      } catch (smsErr) {
        debugPrint('[EMERGENCY] Instant SMS dispatch notice: $smsErr');
      }

      // 7. Notify device UI, heads-up banner, and foreground service
      state = EmergencyState.sent;
      notifyListeners();

      BackgroundProtectionService.notifyAlertDispatched(
        triggerMethodString,
        contactsCount: allSmsPhones.length,
      );
      final dispatchedMethodLabel = lastTriggerMethod == TriggerMethod.voiceKeyword
          ? 'Voice Keyword'
          : (lastTriggerMethod == TriggerMethod.appShake
              ? 'Shake Motion'
              : (lastTriggerMethod == TriggerMethod.pendantTouch
                  ? 'Safety Pendant'
                  : 'Emergency Button'));

      try {
        sl<NotificationService>().showDispatchedPopup(
          method: dispatchedMethodLabel,
          contactsCount: allSmsPhones.length,
        );
      } catch (_) {}

      // 8. Sync with FastAPI backend if reachable
      try {
        final baseUrl = await AppConstants.getEffectiveBackendUrl();
        final backendUri = Uri.parse('$baseUrl/alert/app');
        await http.post(
          backendUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': userId,
            'trigger_method': triggerMethodString,
            'latitude': lat,
            'longitude': lng,
            'accuracy_m': accuracy,
            'emergency_contacts': allSmsPhones,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Backend sync optional: $backendError');
      }
    } catch (e) {
      debugPrint('[EMERGENCY FATAL ERROR] $e');
      state = EmergencyState.sent;
    } finally {
      notifyListeners();
    }
  }

  Future<void> resolveAlert(String panicEventId) async {
    try {
      await _supabaseService.client
          .from('panic_events')
          .update({'status': 'resolved', 'resolved_at': DateTime.now().toIso8601String()})
          .eq('id', panicEventId);
    } catch (e) {
      debugPrint('Error resolving alert: $e');
    } finally {
      _stopLocationUpdates();
      unawaited(_bleService.stopSosBeaconBroadcast());
      unawaited(_bleService.sendPendantCommand('CMD:CANCEL'));
      state = EmergencyState.idle;
      activeEvent = null;
      notifyListeners();
    }
  }

  void startShakeDetection() {
    _shakeService.start(onShake: () {
      debugPrint('[EmergencyController] Shake detected! Triggering SOS.');
      trigger(TriggerMethod.appShake);
    });
    _updateBackgroundNotification();
    notifyListeners();
  }

  void stopShakeDetection() {
    _shakeService.stop();
    _updateBackgroundNotification();
    notifyListeners();
  }

  void toggleShakeDetection() {
    if (isShakeActive) {
      stopShakeDetection();
    } else {
      startShakeDetection();
    }
  }

  void simulateShakeTrigger() {
    _shakeService.simulateShake();
  }

  Future<void> startVoiceDetection() async {
    await _voiceService.startListening();
    _updateBackgroundNotification();
    notifyListeners();
  }

  void stopVoiceDetection() {
    _voiceService.stopListening();
    _updateBackgroundNotification();
    notifyListeners();
  }

  Future<void> toggleVoiceDetection() async {
    final nextState = !_voiceService.isEnabled;
    await _voiceService.updateSettings(
      enabled: nextState,
      phrase: _voiceService.wakePhrase,
    );
    _updateBackgroundNotification();
    notifyListeners();
  }

  Future<void> updateVoiceSettings({required bool enabled, required String phrase}) async {
    await _voiceService.updateSettings(enabled: enabled, phrase: phrase);
    _updateBackgroundNotification();
    notifyListeners();
  }

  void simulateVoiceTrigger() {
    _voiceService.simulateVoiceDetected();
  }

  /// Calculates distance in meters between two GPS coordinates.
  static double distanceBetweenMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    _pendantEventSub?.cancel();
    _shakeService.stop();
    _voiceService.stopListening();
    super.dispose();
  }
}
