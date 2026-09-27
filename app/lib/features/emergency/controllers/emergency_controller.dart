import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../models/panic_event_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/di/service_locator.dart';
import '../services/shake_detector_service.dart';
import '../services/voice_activation_service.dart';

enum EmergencyState { idle, triggered, countdown, sending, sent, failed, cancelled }

enum TriggerMethod { button, appShake, pendantTouch, voice, duressPin }

class EmergencyController extends ChangeNotifier {
  EmergencyState state = EmergencyState.idle;
  TriggerMethod activeTriggerMethod = TriggerMethod.button;
  int countdownSeconds = 10;
  PanicEventModel? activeEvent;
  Timer? _countdownTimer;

  final SupabaseService _supabaseService = sl<SupabaseService>();
  final LocationService _locationService = sl<LocationService>();

  bool get isShakeActive => ShakeDetectorService.instance.isListening;
  bool get isShakeEnabled => ShakeDetectorService.instance.isEnabled;

  bool get isVoiceActive => VoiceActivationService.instance.isListening;
  bool get isVoiceEnabled => VoiceActivationService.instance.isEnabled;
  String get voicePhrase => VoiceActivationService.instance.wakePhrase;

  EmergencyController() {
    _initBackgroundTriggers();
  }

  Future<void> _initBackgroundTriggers() async {
    // Connect shake trigger callback
    await ShakeDetectorService.instance.init(
      onDetected: () {
        debugPrint('📳 [SHAKE EVENT] Triggering SOS countdown via 3-shake detection');
        trigger(TriggerMethod.appShake);
      },
    );

    // Connect voice trigger callback
    await VoiceActivationService.instance.init(
      onDetected: () {
        debugPrint('🎙️ [VOICE EVENT] Triggering SOS countdown via wake word');
        trigger(TriggerMethod.voice);
      },
    );
  }

  Future<void> trigger(TriggerMethod method) async {
    if (state == EmergencyState.triggered ||
        state == EmergencyState.countdown ||
        state == EmergencyState.sending) {
      return;
    }

    activeTriggerMethod = method;
    state = EmergencyState.countdown;
    countdownSeconds = 10;
    notifyListeners();

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
      if (user == null) throw Exception('Not logged in');

      // 1. Get real GPS location
      Position? pos;
      try {
        pos = await _locationService.getCurrentPosition();
      } catch (e) {
        debugPrint('[LOCATION] Could not get GPS: $e');
      }

      final double lat = pos?.latitude ?? -1.2825;
      final double lng = pos?.longitude ?? 36.8222;
      final double accuracy = pos?.accuracy ?? 15.0;

      // 2. Map trigger method
      final String triggerStr = switch (activeTriggerMethod) {
        TriggerMethod.button => 'app_button',
        TriggerMethod.appShake => 'shake',
        TriggerMethod.voice => 'voice',
        TriggerMethod.pendantTouch => 'pendant_touch',
        TriggerMethod.duressPin => 'duress_pin',
      };

      String? panicEventId;

      // 3. Send to FastAPI backend via ngrok
      try {
        final baseUrl = await AppConstants.getEffectiveBackendUrl();
        final backendUri = Uri.parse('$baseUrl/alert/app');
        debugPrint('[BACKEND] Sending alert to: $backendUri (method: $triggerStr)');

        final backendRes = await http.post(
          backendUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': user.id,
            'trigger_method': triggerStr,
            'latitude': lat,
            'longitude': lng,
            'accuracy_m': accuracy,
          }),
        ).timeout(const Duration(seconds: 8));

        if (backendRes.statusCode == 200 || backendRes.statusCode == 201) {
          debugPrint('[BACKEND SUCCESS] Alert processed by backend: ${backendRes.body}');
          final data = jsonDecode(backendRes.body);
          panicEventId = data['panic_event_id'];
        } else {
          debugPrint('[BACKEND NOTICE] Backend returned status ${backendRes.statusCode}: ${backendRes.body}');
        }
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Direct backend call failed: $backendError, falling back to direct Supabase');
      }

      // 4. Complete panic event model
      if (panicEventId != null) {
        try {
          final row = await _supabaseService.client
              .from('panic_events')
              .select()
              .eq('id', panicEventId)
              .maybeSingle();
          if (row != null) {
            activeEvent = PanicEventModel.fromJson(row);
          }
        } catch (_) {}
      } else {
        // Fallback: direct Supabase insert
        final eventData = {
          'user_id': user.id,
          'trigger_method': triggerStr,
          'latitude': lat,
          'longitude': lng,
          'location_accuracy_m': accuracy,
          'status': 'active',
        };

        final response = await _supabaseService.client
            .from('panic_events')
            .insert(eventData)
            .select()
            .single();

        activeEvent = PanicEventModel.fromJson(response);
        panicEventId = activeEvent?.id;
      }

      // 5. Save realtime GPS log if position exists
      if (pos != null && panicEventId != null) {
        try {
          await _locationService.saveGpsLog(panicEventId, pos, user.id);
        } catch (e) {
          debugPrint('[GPS LOG] Save log error: $e');
        }
      }

      state = EmergencyState.sent;
    } catch (e) {
      debugPrint('Error sending alert: $e');
      state = EmergencyState.failed;
    } finally {
      notifyListeners();
    }
  }

  Future<void> resolveAlert(String panicEventId) async {
    try {
      await _supabaseService.client
          .from('panic_events')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', panicEventId);

      state = EmergencyState.idle;
      activeEvent = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resolving alert: $e');
    }
  }

  Future<void> setShakeEnabled(bool enabled) async {
    await ShakeDetectorService.instance.setEnabled(enabled);
    notifyListeners();
  }

  Future<void> updateVoiceSettings({required bool enabled, required String phrase}) async {
    await VoiceActivationService.instance.updateSettings(enabled: enabled, phrase: phrase);
    notifyListeners();
  }

  void startShakeDetection() {
    ShakeDetectorService.instance.startListening();
    notifyListeners();
  }

  void stopShakeDetection() {
    ShakeDetectorService.instance.stopListening();
    notifyListeners();
  }
}
