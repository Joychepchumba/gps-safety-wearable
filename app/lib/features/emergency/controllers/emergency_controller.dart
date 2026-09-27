import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../models/panic_event_model.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/navigation/navigation_service.dart';
import '../../../core/di/service_locator.dart';
import '../services/shake_detector_service.dart';
import '../services/voice_activation_service.dart';

enum EmergencyState { idle, triggered, countdown, sending, sent, failed, cancelled }

enum TriggerMethod { button, appShake, pendantTouch, voice, duressPin }

class EmergencyController extends ChangeNotifier {
  EmergencyState state = EmergencyState.idle;
  TriggerMethod activeTriggerMethod = TriggerMethod.button;
  int countdownSeconds = 6;
  PanicEventModel? activeEvent;
  Timer? _countdownTimer;

  // Real-Time 3D Location Sharing during Emergency (Default 8 Hours)
  String? activeTrackingUrl;
  String? activeSessionToken;
  bool isSharingLocation = false;
  Timer? _emergencyPingTimer;

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

    // Navigate to full-screen emergency mode immediately
    NavigationService.pushNamed('/emergency');

    if (method == TriggerMethod.voice) {
      // Voice activation is always intentional - rapid 1s confirmation then dispatch
      state = EmergencyState.countdown;
      countdownSeconds = 1;
      notifyListeners();

      HapticFeedback.heavyImpact();
      _startCountdownVibration(short: true);

      _countdownTimer?.cancel();
      _countdownTimer = Timer(const Duration(seconds: 1), () {
        _stopVibration();
        _sendAlert();
      });
      return;
    }

    // Shake or Button: Provide cancel countdown with prominent vibration
    // For shake: 6s countdown to easily cancel accidental shakes
    state = EmergencyState.countdown;
    countdownSeconds = (method == TriggerMethod.appShake) ? 6 : 5;
    notifyListeners();

    _startCountdownVibration();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds > 1) {
        countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _stopVibration();
        _sendAlert();
      }
    });
  }

  void sendImmediately() {
    if (state == EmergencyState.countdown) {
      _countdownTimer?.cancel();
      _stopVibration();
      _sendAlert();
    }
  }

  void cancel() {
    if (state == EmergencyState.countdown) {
      _countdownTimer?.cancel();
      _stopVibration();
      state = EmergencyState.cancelled;
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 600), () {
        state = EmergencyState.idle;
        notifyListeners();
        NavigationService.pop();
      });
    }
  }

  void _startCountdownVibration({bool short = false}) async {
    try {
      final hasVib = await Vibration.hasVibrator();
      if (hasVib == true) {
        if (short) {
          Vibration.vibrate(pattern: [0, 200, 100, 300]);
        } else {
          // Continuous rhythmic buzzing during shake countdown
          Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400], repeat: 0);
        }
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  void _stopVibration() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
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
          activeTrackingUrl = data['tracking_url'];
          activeSessionToken = data['session_token'];
          if (activeTrackingUrl != null) {
            isSharingLocation = true;
          }
        } else {
          debugPrint('[BACKEND NOTICE] Backend returned status ${backendRes.statusCode}: ${backendRes.body}');
        }
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Direct backend call failed: $backendError, falling back to direct Supabase');
      }

      // If tracking url was not returned, start an 8-hour session directly
      if (activeTrackingUrl == null) {
        try {
          final baseUrl = await AppConstants.getEffectiveBackendUrl();
          final shareUri = Uri.parse('$baseUrl/gps/share/start');
          final shareRes = await http.post(
            shareUri,
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: jsonEncode({
              'user_id': user.id,
              'duration_hours': 8,
              'latitude': lat,
              'longitude': lng,
              'accuracy_m': accuracy,
              'is_emergency': true,
              'activity_name': '🚨 EMERGENCY SOS',
            }),
          ).timeout(const Duration(seconds: 4));
          if (shareRes.statusCode == 200) {
            final sData = jsonDecode(shareRes.body);
            activeTrackingUrl = sData['tracking_url'];
            activeSessionToken = sData['session_token'];
            isSharingLocation = true;
          }
        } catch (_) {}
      }

      // Start periodic 8-second GPS ping loop to update the 3D Mapbox tracking page in real-time
      _startEmergencyPingTimer(user.id);

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

      // 6. Direct Community Responder fallback notification
      if (panicEventId != null) {
        try {
          final res = await _supabaseService.client
              .from('users')
              .select('id')
              .eq('is_community_responder', true)
              .neq('id', user.id);
          final responders = res as List;
          if (responders.isNotEmpty) {
            final toInsert = responders.map((r) => {
              'panic_event_id': panicEventId,
              'responder_id': r['id'],
              'distance_m': 250.0,
            }).toList();
            await _supabaseService.client
                .from('responder_alerts')
                .upsert(toInsert, onConflict: 'panic_event_id,responder_id');
            debugPrint('[COMMUNITY] Successfully alerted ${toInsert.length} responders');
          }
        } catch (re) {
          debugPrint('[COMMUNITY] Direct responder notification notice: $re');
        }
      }

      state = EmergencyState.sent;
      _stopVibration();

      // Clear, unmistakable alert sent confirmation (distinct triple pulse + alert tone)
      try {
        final hasVib = await Vibration.hasVibrator();
        if (hasVib == true) {
          Vibration.vibrate(pattern: [0, 300, 150, 300, 150, 600]);
        } else {
          HapticFeedback.heavyImpact();
        }
      } catch (_) {
        HapticFeedback.heavyImpact();
      }
      SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('Error sending alert: $e');
      state = EmergencyState.failed;
      _stopVibration();
    } finally {
      notifyListeners();
    }
  }

  Future<void> resolveAlert(String panicEventId) async {
    _stopVibration();
    _emergencyPingTimer?.cancel();
    _emergencyPingTimer = null;
    isSharingLocation = false;
    activeTrackingUrl = null;
    activeSessionToken = null;

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

  void _startEmergencyPingTimer(String userId) {
    _emergencyPingTimer?.cancel();
    _emergencyPingTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (state != EmergencyState.sent || !isSharingLocation) {
        _emergencyPingTimer?.cancel();
        return;
      }
      try {
        final pos = await _locationService.getCurrentPosition();
        if (pos != null) {
          final baseUrl = await AppConstants.getEffectiveBackendUrl();
          final pingUri = Uri.parse('$baseUrl/gps/ping');
          await http.post(
            pingUri,
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: jsonEncode({
              'user_id': userId,
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'accuracy_m': pos.accuracy,
              'speed': pos.speed,
              'altitude': pos.altitude,
              'session_token': activeSessionToken,
            }),
          ).timeout(const Duration(seconds: 4));
        }
      } catch (_) {}
    });
  }

  Future<void> cancelRealTimeSharing() async {
    isSharingLocation = false;
    _emergencyPingTimer?.cancel();
    _emergencyPingTimer = null;
    notifyListeners();

    final user = _supabaseService.client.auth.currentUser;
    if (user != null) {
      try {
        final baseUrl = await AppConstants.getEffectiveBackendUrl();
        final stopUri = Uri.parse('$baseUrl/gps/share/stop');
        await http.post(
          stopUri,
          headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
          body: jsonEncode({
            'user_id': user.id,
            'session_token': activeSessionToken,
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}
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
