import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/panic_event_model.dart';
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

      // 1. Get location (stub)
      const double lat = -1.2921;
      const double lng = 36.8219;

      // 2. Create panic event
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

      // 3-7. Stubs for streaming GPS, getting contacts, sending SMS, push notifications
      await Future.delayed(const Duration(seconds: 2));

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
