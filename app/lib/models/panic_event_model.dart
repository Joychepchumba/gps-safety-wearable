class PanicEventModel {
  final String id;
  final String userId;
  final String? wearableDeviceId;
  final DateTime triggeredAt;
  final String triggerMethod;
  final String status;
  final DateTime? resolvedAt;
  final double latitude;
  final double longitude;
  final double locationAccuracyM;
  final bool isLocationAnonymised;
  final DateTime? anonymisedAt;
  final bool emergencyContactsNotified;
  final bool hotlineNotified;
  final bool communityRespondersAlerted;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PanicEventModel({
    required this.id,
    required this.userId,
    this.wearableDeviceId,
    required this.triggeredAt,
    required this.triggerMethod,
    required this.status,
    this.resolvedAt,
    required this.latitude,
    required this.longitude,
    required this.locationAccuracyM,
    required this.isLocationAnonymised,
    this.anonymisedAt,
    required this.emergencyContactsNotified,
    required this.hotlineNotified,
    required this.communityRespondersAlerted,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PanicEventModel.fromJson(Map<String, dynamic> json) {
    return PanicEventModel(
      id: json['id'],
      userId: json['user_id'],
      wearableDeviceId: json['wearable_device_id'],
      triggeredAt: DateTime.parse(json['triggered_at']),
      triggerMethod: json['trigger_method'] ?? 'app',
      status: json['status'] ?? 'active',
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at']) : null,
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      locationAccuracyM: json['location_accuracy_m']?.toDouble() ?? 0.0,
      isLocationAnonymised: json['is_location_anonymised'] ?? false,
      anonymisedAt: json['anonymised_at'] != null ? DateTime.parse(json['anonymised_at']) : null,
      emergencyContactsNotified: json['emergency_contacts_notified'] ?? false,
      hotlineNotified: json['hotline_notified'] ?? false,
      communityRespondersAlerted: json['community_responders_alerted'] ?? false,
      notes: json['notes'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'wearable_device_id': wearableDeviceId,
      'triggered_at': triggeredAt.toIso8601String(),
      'trigger_method': triggerMethod,
      'status': status,
      'resolved_at': resolvedAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'location_accuracy_m': locationAccuracyM,
      'is_location_anonymised': isLocationAnonymised,
      'anonymised_at': anonymisedAt?.toIso8601String(),
      'emergency_contacts_notified': emergencyContactsNotified,
      'hotline_notified': hotlineNotified,
      'community_responders_alerted': communityRespondersAlerted,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PanicEventModel copyWith({
    String? id,
    String? userId,
    String? wearableDeviceId,
    DateTime? triggeredAt,
    String? triggerMethod,
    String? status,
    DateTime? resolvedAt,
    double? latitude,
    double? longitude,
    double? locationAccuracyM,
    bool? isLocationAnonymised,
    DateTime? anonymisedAt,
    bool? emergencyContactsNotified,
    bool? hotlineNotified,
    bool? communityRespondersAlerted,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PanicEventModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      wearableDeviceId: wearableDeviceId ?? this.wearableDeviceId,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      triggerMethod: triggerMethod ?? this.triggerMethod,
      status: status ?? this.status,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyM: locationAccuracyM ?? this.locationAccuracyM,
      isLocationAnonymised: isLocationAnonymised ?? this.isLocationAnonymised,
      anonymisedAt: anonymisedAt ?? this.anonymisedAt,
      emergencyContactsNotified: emergencyContactsNotified ?? this.emergencyContactsNotified,
      hotlineNotified: hotlineNotified ?? this.hotlineNotified,
      communityRespondersAlerted: communityRespondersAlerted ?? this.communityRespondersAlerted,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
