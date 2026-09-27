import 'dart:math';

class PoliceStationModel {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final String phoneNumber;
  final String? county;

  PoliceStationModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.phoneNumber = '0800720999',
    this.county,
  });

  factory PoliceStationModel.fromJson(Map<String, dynamic> json) {
    return PoliceStationModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? 'Police Station',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      phoneNumber: json['phone_number'] ?? json['phone'] ?? '0800720999',
      county: json['county'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'phone_number': phoneNumber,
      'county': county,
    };
  }

  /// Calculates great-circle distance in metres using Haversine formula
  double distanceTo(double userLat, double userLng) {
    const double r = 6371000.0; // Earth mean radius in metres
    final dLat = (latitude - userLat) * pi / 180.0;
    final dLng = (longitude - userLng) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(userLat * pi / 180.0) * cos(latitude * pi / 180.0) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Formatted friendly distance label: "350m away" or "2.4 km away"
  String formattedDistance(double userLat, double userLng) {
    final metres = distanceTo(userLat, userLng);
    if (metres < 1000) {
      return '${metres.toStringAsFixed(0)}m away';
    }
    return '${(metres / 1000).toStringAsFixed(1)} km away';
  }

  /// Curated default police stations dataset for Kenya (Nairobi and major hubs)
  static List<PoliceStationModel> defaultKenyaStations() {
    return [
      PoliceStationModel(id: 1, name: 'Central Police Station (CBD)', latitude: -1.2825, longitude: 36.8222, phoneNumber: '0202222222', county: 'Nairobi'),
      PoliceStationModel(id: 2, name: 'Kilimani Police Station', latitude: -1.2917, longitude: 36.7865, phoneNumber: '0202722888', county: 'Nairobi'),
      PoliceStationModel(id: 3, name: 'Gigiri Police Station', latitude: -1.2330, longitude: 36.8040, phoneNumber: '0203746666', county: 'Nairobi'),
      PoliceStationModel(id: 4, name: 'Parklands Police Station', latitude: -1.2612, longitude: 36.8193, phoneNumber: '0203741212', county: 'Nairobi'),
      PoliceStationModel(id: 5, name: 'Langata Police Station', latitude: -1.3363, longitude: 36.7450, phoneNumber: '020891000', county: 'Nairobi'),
      PoliceStationModel(id: 6, name: 'Kasarani Police Station', latitude: -1.2215, longitude: 36.9015, phoneNumber: '0208560000', county: 'Nairobi'),
      PoliceStationModel(id: 7, name: 'Embakasi Police Station', latitude: -1.3116, longitude: 36.8851, phoneNumber: '020822000', county: 'Nairobi'),
      PoliceStationModel(id: 8, name: 'Industrial Area Police Station', latitude: -1.3050, longitude: 36.8480, phoneNumber: '020556000', county: 'Nairobi'),
      PoliceStationModel(id: 9, name: 'Westlands Police Post', latitude: -1.2680, longitude: 36.8070, phoneNumber: '020444000', county: 'Nairobi'),
      PoliceStationModel(id: 10, name: 'Dagoretti Police Station', latitude: -1.2961, longitude: 36.7070, phoneNumber: '020387000', county: 'Nairobi'),
      PoliceStationModel(id: 11, name: 'Mombasa Central Police Station', latitude: -4.0680, longitude: 39.6658, phoneNumber: '0412222222', county: 'Mombasa'),
      PoliceStationModel(id: 12, name: 'Kisumu Central Police Station', latitude: -0.1041, longitude: 34.7568, phoneNumber: '0572022222', county: 'Kisumu'),
      PoliceStationModel(id: 13, name: 'Nakuru Central Police Station', latitude: -0.2823, longitude: 36.0667, phoneNumber: '0512211000', county: 'Nakuru'),
      PoliceStationModel(id: 14, name: 'Eldoret Central Police Station', latitude: 0.5143, longitude: 35.2698, phoneNumber: '0532062000', county: 'Uasin Gishu'),
    ];
  }
}
