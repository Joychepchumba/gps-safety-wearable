import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

class SupabaseConfig {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    final url = AppConstants.supabaseUrl.isNotEmpty
        ? AppConstants.supabaseUrl
        : 'https://placeholder-project.supabase.co';
    final anonKey = AppConstants.supabaseAnonKey.isNotEmpty
        ? AppConstants.supabaseAnonKey
        : 'placeholder-anon-key';

    try {
      await Supabase.initialize(
        url: url,
        publishableKey: anonKey,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('Supabase initialization notice: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
