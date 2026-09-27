class CommunityAlertModel {
  final String panicEventId;
  final String userName;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String mapsLink;
  final String triggerMethod;
  final DateTime triggeredAt;
  final String status;

  CommunityAlertModel({
    required this.panicEventId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.mapsLink,
    required this.triggerMethod,
    required this.triggeredAt,
    required this.status,
  });

  factory CommunityAlertModel.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (json['longitude'] as num?)?.toDouble() ?? 0.0;

    return CommunityAlertModel(
      panicEventId: json['panic_event_id']?.toString() ?? json['id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? 'SafeLink User',
      latitude: lat,
      longitude: lng,
      distanceMeters: (json['distance_m'] as num?)?.toDouble() ?? 0.0,
      mapsLink: json['maps_link']?.toString() ?? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      triggerMethod: json['trigger_method']?.toString() ?? 'emergency',
      triggeredAt: json['triggered_at'] != null
          ? (DateTime.tryParse(json['triggered_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      status: json['status']?.toString() ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'panic_event_id': panicEventId,
      'user_name': userName,
      'latitude': latitude,
      'longitude': longitude,
      'distance_m': distanceMeters,
      'maps_link': mapsLink,
      'trigger_method': triggerMethod,
      'triggered_at': triggeredAt.toIso8601String(),
      'status': status,
    };
  }

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)} m away';
    } else {
      final km = distanceMeters / 1000.0;
      return '${km.toStringAsFixed(1)} km away';
    }
  }
}
