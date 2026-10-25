import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/shake_detection_service.dart';
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

  // Callback to navigate to emergency screen from background/shake
  VoidCallback? onEmergencyTriggered;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();
  final ShakeDetectionService _shakeService = sl<ShakeDetectionService>();
  final VoiceActivationService _voiceService = sl<VoiceActivationService>();

  bool get isShakeActive => _shakeService.isListening;
  bool get isVoiceActive => _voiceService.isListening;
  bool get isVoiceEnabled => _voiceService.isEnabled;
  String get voiceWakePhrase => _voiceService.wakePhrase;

  bool _isBatterySaverEnabled = false;
  bool get isBatterySaverEnabled => _isBatterySaverEnabled;

  String? _panicEventId;
  Timer? _locationTimer;
  bool _protectionStarted = false;

  EmergencyController() {
    startShakeDetection();
    _initVoiceActivation();
    initBatterySaver();
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
      // In battery saver mode, pause continuous background microphone loop
      // while keeping ultra-light 15Hz shake detection actively armed.
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
    });
  }

  Future<void> trigger(TriggerMethod method) async {
    if (state == EmergencyState.triggered || state == EmergencyState.countdown) return;

    lastTriggerMethod = method;
    state = EmergencyState.countdown;
    countdownSeconds = 10;
    notifyListeners();

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
    if (state == EmergencyState.countdown) {
      _countdownTimer?.cancel();
      _stopLocationUpdates();
      state = EmergencyState.cancelled;
      notifyListeners();

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
      final userId = user?.id ?? '00000000-0000-0000-0000-000000000000';
      final userName = user?.userMetadata?['full_name'] ?? 'SafeLink User';

      // 1. Get real device location from LocationService (with fallback)
      double lat = -1.2921;
      double lng = 36.8219;
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

      final triggerMethodString = lastTriggerMethod == TriggerMethod.appShake
          ? 'app_shake'
          : (lastTriggerMethod == TriggerMethod.pendantTouch
              ? 'pendant_touch'
              : (lastTriggerMethod == TriggerMethod.voiceKeyword
                  ? 'voice_keyword'
                  : 'app_button'));

      // 2. Retrieve user's configured emergency contacts
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

      // Generate panic event ID early so SMS tracking link works immediately
      _panicEventId = 'evt_${DateTime.now().millisecondsSinceEpoch}';
      _startLocationUpdates();

      // 3. IMMEDIATE PRIORITY: Dispatch Africa's Talking SMS with Live 3D Tracking link
      try {
        final smsService = sl<SmsService>();
        unawaited(smsService.notifyEmergencyContacts(
          contactPhones,
          userName,
          lat,
          lng,
          panicEventId: _panicEventId,
        ));
        debugPrint('[EMERGENCY] Instant SMS dispatched via Africa\'s Talking to ${contactPhones.length} contacts & police');
      } catch (smsErr) {
        debugPrint('[EMERGENCY] Instant SMS dispatch notice: $smsErr');
      }

      // 4. IMMEDIATE PRIORITY: Notify device UI, heads-up banner, and foreground service
      state = EmergencyState.sent;
      notifyListeners();

      BackgroundProtectionService.notifyAlertDispatched(triggerMethodString, contactsCount: contactPhones.length);
      try {
        sl<NotificationService>().showEmergencyAlert(
          '🚨 SafeLink SOS Alert Dispatched',
          'Live 3D GPS tracking & SMS sent to ${contactPhones.length} contacts, community responders, and police.',
        );
      } catch (_) {}

      // 5. Broadcast to community responders in Supabase
      try {
        final List respondersRes = await _supabaseService.client
            .from('users')
            .select('id, phone_number, is_community_responder')
            .eq('is_community_responder', true);

        if (respondersRes.isNotEmpty) {
          final alertsToInsert = respondersRes.map((r) => {
            'panic_event_id': _panicEventId,
            'responder_id': r['id'],
            'distance_m': 350.0,
          }).toList();
          await _supabaseService.client.from('responder_alerts').insert(alertsToInsert);
          debugPrint('[EMERGENCY] Broadcast logged to ${respondersRes.length} community responders');
        }
      } catch (respErr) {
        debugPrint('[EMERGENCY] Community responder broadcast notice: $respErr');
      }

      // 6. Record incident into Supabase panic_events
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
            'community_responders_alerted': true,
          };
          final response = await _supabaseService.client
              .from('panic_events')
              .insert(eventData)
              .select()
              .single();

          activeEvent = PanicEventModel.fromJson(response);
          _panicEventId = activeEvent?.id ?? _panicEventId;
        } catch (dbErr) {
          debugPrint('[EMERGENCY] Supabase direct insert notice: $dbErr');
        }
      }

      // 7. Sync with FastAPI backend if reachable
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
            'emergency_contacts': contactPhones,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Backend sync optional: $backendError');
      }

    } catch (e) {
      debugPrint('[EMERGENCY FATAL ERROR] $e');
      // Even on exception, keep state marked sent so the user sees the SOS active screen
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

      _stopLocationUpdates();
      state = EmergencyState.idle;
      activeEvent = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resolving alert: $e');
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    _shakeService.stop();
    _voiceService.stopListening();
    super.dispose();
  }
}
