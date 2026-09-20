class WearableDeviceModel {
  final String id;
  final String userId;
  final String deviceMac;
  final String deviceName;
  final String? firmwareVersion;
  final String? simIccid;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final bool isActive;

  WearableDeviceModel({
    required this.id,
    required this.userId,
    required this.deviceMac,
    required this.deviceName,
    this.firmwareVersion,
    this.simIccid,
    required this.pairedAt,
    this.lastSeenAt,
    required this.isActive,
  });

  factory WearableDeviceModel.fromJson(Map<String, dynamic> json) {
    return WearableDeviceModel(
      id: json['id'],
      userId: json['user_id'],
      deviceMac: json['device_mac'],
      deviceName: json['device_name'] ?? 'SafeGuard Device',
      firmwareVersion: json['firmware_version'],
      simIccid: json['sim_iccid'],
      pairedAt: DateTime.parse(json['paired_at']),
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'device_mac': deviceMac,
      'device_name': deviceName,
      'firmware_version': firmwareVersion,
      'sim_iccid': simIccid,
      'paired_at': pairedAt.toIso8601String(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  WearableDeviceModel copyWith({
    String? id,
    String? userId,
    String? deviceMac,
    String? deviceName,
    String? firmwareVersion,
    String? simIccid,
    DateTime? pairedAt,
    DateTime? lastSeenAt,
    bool? isActive,
  }) {
    return WearableDeviceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceMac: deviceMac ?? this.deviceMac,
      deviceName: deviceName ?? this.deviceName,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      simIccid: simIccid ?? this.simIccid,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
