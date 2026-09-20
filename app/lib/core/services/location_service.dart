import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  Future<Position?> getCurrentPosition() async {
    bool hasPermission = await requestPermission();
    if (!hasPermission) return null;
    return await Geolocator.getCurrentPosition();
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream();
  }

  Future<void> saveGpsLog(String panicEventId, Position pos, String userId) async {
    await _client.from('realtime_gps_logs').insert({
      'panic_event_id': panicEventId,
      'user_id': userId,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy_m': pos.accuracy,
      'recorded_at': DateTime.now().toIso8601String(),
    });
  }
}
