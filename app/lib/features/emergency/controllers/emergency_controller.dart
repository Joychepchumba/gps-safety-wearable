import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/panic_event_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/di/service_locator.dart';

enum EmergencyState { idle, triggered, countdown, sending, sent, failed, cancelled }

enum TriggerMethod { button, appShake, pendantTouch }

class EmergencyController extends ChangeNotifier {
  EmergencyState state = EmergencyState.idle;
  int countdownSeconds = 10;
  PanicEventModel? activeEvent;
  Timer? _countdownTimer;

  final SupabaseService _supabaseService = sl<SupabaseService>();

  Future<void> trigger(TriggerMethod method) async {
    if (state == EmergencyState.triggered || state == EmergencyState.countdown) return;
    
    state = EmergencyState.countdown;
    countdownSeconds = 10;
    notifyListeners();

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

      // 1. Get location (stub or geolocator)
      const double lat = -1.2921;
      const double lng = 36.8219;

      // 2. Send to FastAPI backend via ngrok
      try {
        final baseUrl = await AppConstants.getEffectiveBackendUrl();
        final backendUri = Uri.parse('$baseUrl/alert/app');
        debugPrint('[BACKEND] Sending alert to: $backendUri');
        final backendRes = await http.post(
          backendUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': user.id,
            'trigger_method': 'app_button',
            'latitude': lat,
            'longitude': lng,
            'accuracy_m': 15.0,
          }),
        ).timeout(const Duration(seconds: 8));

        if (backendRes.statusCode == 200 || backendRes.statusCode == 201) {
          debugPrint('[BACKEND SUCCESS] Alert processed by backend: ${backendRes.body}');
          state = EmergencyState.sent;
          notifyListeners();
          return;
        } else {
          debugPrint('[BACKEND NOTICE] Backend returned status ${backendRes.statusCode}: ${backendRes.body}');
        }
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Direct backend call failed: $backendError, falling back to direct Supabase');
      }

      // Fallback: direct Supabase insert
      final eventData = {
        'user_id': user.id,
        'trigger_method': 'app_button',
        'latitude': lat,
        'longitude': lng,
        'status': 'active'
      };

      final response = await _supabaseService.client
          .from('panic_events')
          .insert(eventData)
          .select()
          .single();

      activeEvent = PanicEventModel.fromJson(response);
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
          .update({'status': 'resolved', 'resolved_at': DateTime.now().toIso8601String()})
          .eq('id', panicEventId);
          
      state = EmergencyState.idle;
      activeEvent = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resolving alert: $e');
    }
  }

  void startShakeDetection() {
    // Stub
  }

  void stopShakeDetection() {
    // Stub
  }
}
