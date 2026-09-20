import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../../../models/panic_event_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/di/service_locator.dart';

class HomeController extends ChangeNotifier {
  UserModel? user;
  bool isBleConnected = false;
  bool isResponderMode = false;
  List<PanicEventModel> recentAlerts = [];
  bool isLoading = false;
  String? message;

  final SupabaseService _supabaseService = sl<SupabaseService>();

  HomeController() {
    loadUser();
    listenToBleStatus();
    loadRecentAlerts();
  }

  Future<void> loadUser() async {
    isLoading = true;
    notifyListeners();
    try {
      final authUser = _supabaseService.currentUser;
      if (authUser == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      user = await _supabaseService.fetchUserProfile(authUser.id);
      isResponderMode = user?.isCommunityResponder ?? false;
    } catch (e) {
      debugPrint('Error loading user: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleResponderMode(bool value) async {
    if (user == null) return;
    try {
      await _supabaseService.toggleCommunityResponder(userId: user!.id, optIn: value);
      isResponderMode = value;
      user = await _supabaseService.fetchUserProfile(user!.id);
      message = value
          ? 'You are now an active Community Responder.'
          : 'You opted out of Community Response.';
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling responder mode: $e');
    }
  }

  Future<bool> setEmergencyPassword(String duressPassword) async {
    if (user == null) return false;
    try {
      await _supabaseService.updateEmergencyPassword(
        userId: user!.id,
        emergencyPassword: duressPassword,
      );
      user = await _supabaseService.fetchUserProfile(user!.id);
      message = 'Emergency duress code updated successfully.';
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating duress password: $e');
      return false;
    }
  }

  void listenToBleStatus() {
    isBleConnected = false;
    notifyListeners();
  }

  Future<void> loadRecentAlerts() async {
    try {
      final authUser = _supabaseService.currentUser;
      if (authUser == null) return;

      final data = await _supabaseService.client
          .from('panic_events')
          .select()
          .eq('user_id', authUser.id)
          .order('triggered_at', ascending: false)
          .limit(5);

      recentAlerts = (data as List).map((e) => PanicEventModel.fromJson(e)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading recent alerts: $e');
    }
  }
}
