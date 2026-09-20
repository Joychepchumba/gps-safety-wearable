import 'package:flutter/material.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/di/service_locator.dart';

class AlertController extends ChangeNotifier {
  List<PanicEventModel> alerts = [];
  bool isLoading = false;

  final SupabaseService _supabaseService = sl<SupabaseService>();

  AlertController() {
    loadAlerts();
  }

  Future<void> loadAlerts() async {
    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.currentUser;
      if (user == null) return;

      final data = await _supabaseService.client
          .from('panic_events')
          .select()
          .eq('user_id', user.id)
          .order('triggered_at', ascending: false);

      alerts = (data as List).map((e) => PanicEventModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error loading alerts: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAlerts() async {
    await loadAlerts();
  }
}
