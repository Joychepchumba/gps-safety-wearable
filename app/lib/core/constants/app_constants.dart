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

  static const String bleServiceUUID = 'ffe0';
  static const String bleAlertCharUUID = 'ffe1';
}
