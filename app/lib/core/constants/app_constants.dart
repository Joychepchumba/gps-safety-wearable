import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConstants {
  static const String policeNumber = '0800720999';
  static const double emergencyRadiusMeters = 1000.0;
  static const int panicCountdownSeconds = 10;
  static const int locationAnonymisationHours = 24;

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String africasTalkingApiKey = String.fromEnvironment('AT_API_KEY', defaultValue: '');
  static const String africasTalkingUsername = String.fromEnvironment('AT_USERNAME', defaultValue: 'sandbox');

  static const String backendBaseUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');

  static String? _cachedDynamicBackendUrl;

  /// Resolves the live backend URL:
  /// 1. Checks Supabase `app_config` table for dynamic live ngrok tunnel
  /// 2. Falls back to compile-time --dart-define=BACKEND_URL or localhost
  static Future<String> getEffectiveBackendUrl() async {
    if (_cachedDynamicBackendUrl != null && _cachedDynamicBackendUrl!.isNotEmpty) {
      return _cachedDynamicBackendUrl!;
    }
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'backend_url')
          .maybeSingle();
      if (res != null && res['value'] != null) {
        final val = (res['value'] as String).trim();
        if (val.isNotEmpty && val.startsWith('http')) {
          _cachedDynamicBackendUrl = val;
          debugPrint('[CONFIG] Resolved live backend URL from Supabase: $val');
          return val;
        }
      }
    } catch (_) {}
    return backendBaseUrl;
  }

  static const String bleServiceUUID = 'ffe0';
  static const String bleAlertCharUUID = 'ffe1';
}

