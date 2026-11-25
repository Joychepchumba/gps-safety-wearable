import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConstants {
  static const String policeNumber = '0783711202';
  static const String policeVoiceNumber = '0800720999';
  static const double emergencyRadiusMeters = 1000.0;
  static const int panicCountdownSeconds = 10;
  static const int locationAnonymisationHours = 24;

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://afagwdhpjnnbueiyjmde.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmYWd3ZGhwam5uYnVlaXlqbWRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTkzMzUsImV4cCI6MjEwNTQ5NTMzNX0.Qw_rs_KJOZF8RkXWW62QBKnSafzJFkt9YBPqCRo9mlA',
  );

  static const String africasTalkingApiKey = String.fromEnvironment(
    'AT_API_KEY',
    defaultValue: 'atsk_f15a6b76484db0161cc2558bab88c2c590dda7cd85438f37ee1162513db42382f9f0e688',
  );
  static const String africasTalkingUsername = String.fromEnvironment(
    'AT_USERNAME',
    defaultValue: 'sandbox',
  );

  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: 'pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA',
  );

  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://unpaved-coherent-encroach.ngrok-free.dev',
  );

  static String? _cachedDynamicBackendUrl;

  /// Resolves the live backend URL:
  /// 1. Checks Supabase `app_config` table for dynamic live ngrok tunnel
  /// 2. Falls back to compile-time --dart-define=BACKEND_URL or localhost
  static Future<String> getEffectiveBackendUrl() async {
    if (_cachedDynamicBackendUrl != null &&
        _cachedDynamicBackendUrl!.isNotEmpty) {
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
  static const String bleConfigCharUUID = 'ffe2';
  static const String bleStatusCharUUID = 'ffe3';
  static const int bleSosManufacturerId = 0xFFFF;

  /// Permanent, serverless 3D Mapbox live tracking viewer hosted on GitHub Pages
  static const String trackingViewerBaseUrl = String.fromEnvironment(
    'TRACKING_VIEWER_URL',
    defaultValue:
        'https://joychepchumba.github.io/gps-safety-wearable/track.html',
  );

  /// Builds a permanent 3D Mapbox live tracking link that doesn't rely on ngrok
  static String buildLiveTrackingUrl({
    required double lat,
    required double lng,
    String? name,
    String? session,
    String? alertId,
  }) {
    final queryParams = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lng': lng.toStringAsFixed(6),
    };
    if (name != null && name.isNotEmpty) queryParams['name'] = name;
    if (session != null && session.isNotEmpty) queryParams['session'] = session;
    if (alertId != null && alertId.isNotEmpty) queryParams['id'] = alertId;

    final uri = Uri.parse(trackingViewerBaseUrl)
        .replace(queryParameters: queryParams);
    return uri.toString();
  }
}
