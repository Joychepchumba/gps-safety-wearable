import 'dart:math';

class DangerZoneModel {
  final int id;
  final String locationName;
  final double latitude;
  final double longitude;
  final String description;
  final double radiusMeters;
  final int reportedCount;
  final String riskLevel; // 'high', 'moderate', 'caution'

  DangerZoneModel({
    required this.id,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.description,
    this.radiusMeters = 500.0,
    this.reportedCount = 1,
    this.riskLevel = 'high',
  });

  factory DangerZoneModel.fromJson(Map<String, dynamic> json) {
    return DangerZoneModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      locationName: json['location_name'] ?? json['name'] ?? 'Caution Area',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      description: json['description'] ?? 'Elevated mugging and theft incidents reported.',
      radiusMeters: (json['radius'] as num?)?.toDouble() ?? 500.0,
      reportedCount: json['reported_count'] is int ? json['reported_count'] : 1,
      riskLevel: json['risk_level'] ?? 'high',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_name': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'radius': radiusMeters,
      'reported_count': reportedCount,
      'risk_level': riskLevel,
    };
  }

  /// Calculates great-circle distance in metres to the zone center
  double distanceTo(double userLat, double userLng) {
    const double r = 6371000.0;
    final dLat = (latitude - userLat) * pi / 180.0;
    final dLng = (longitude - userLng) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(userLat * pi / 180.0) * cos(latitude * pi / 180.0) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Checks if the user is inside this geofenced danger zone
  bool containsUser(double userLat, double userLng) {
    return distanceTo(userLat, userLng) <= radiusMeters;
  }

  /// Formatted distance string
  String formattedDistance(double userLat, double userLng) {
    final metres = distanceTo(userLat, userLng);
    if (metres < 1000) {
      return '${metres.toStringAsFixed(0)}m away';
    }
    return '${(metres / 1000).toStringAsFixed(1)} km away';
  }

  /// Curated default danger zones / crime hotspots in Kenya
  static List<DangerZoneModel> defaultDangerZones() {
    return [
      DangerZoneModel(
        id: 1,
        locationName: 'Globe Cinema Roundabout',
        latitude: -1.2785,
        longitude: 36.8188,
        description: 'Frequent snatch-and-grab thefts during rush hours and night.',
        radiusMeters: 400.0,
        riskLevel: 'high',
      ),
      DangerZoneModel(
        id: 2,
        locationName: 'River Road / Luthuli Avenue intersection',
        latitude: -1.2840,
        longitude: 36.8280,
        description: 'Dense crowding, pickpocketing and aggressive harassment hotspot.',
        radiusMeters: 350.0,
        riskLevel: 'high',
      ),
      DangerZoneModel(
        id: 3,
        locationName: 'Kasarani Hunters Underpass',
        latitude: -1.2220,
        longitude: 36.9010,
        description: 'Poor lighting at night, armed robbery incidents reported.',
        radiusMeters: 450.0,
        riskLevel: 'high',
      ),
      DangerZoneModel(
        id: 4,
        locationName: 'Muthurwa Footbridge & Market Area',
        latitude: -1.2880,
        longitude: 36.8340,
        description: 'High rate of bag and phone snatching at dusk.',
        radiusMeters: 400.0,
        riskLevel: 'high',
      ),
      DangerZoneModel(
        id: 5,
        locationName: 'Githurai 45 Roundabout',
        latitude: -1.2010,
        longitude: 36.9310,
        description: 'Congested transit hub with recurrent purse snatching reports.',
        radiusMeters: 500.0,
        riskLevel: 'moderate',
      ),
    ];
  }
}
