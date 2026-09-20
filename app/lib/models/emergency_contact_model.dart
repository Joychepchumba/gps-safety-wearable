class EmergencyContactModel {
  final String id;
  final String userId;
  final String contactName;
  final String phoneNumber;
  final String? email;
  final String consentStatus;
  final DateTime? consentedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmergencyContactModel({
    required this.id,
    required this.userId,
    required this.contactName,
    required this.phoneNumber,
    this.email,
    required this.consentStatus,
    this.consentedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id'],
      userId: json['user_id'],
      contactName: json['contact_name'],
      phoneNumber: json['phone_number'],
      email: json['email'],
      consentStatus: json['consent_status'] ?? 'pending',
      consentedAt: json['consented_at'] != null ? DateTime.parse(json['consented_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'contact_name': contactName,
      'phone_number': phoneNumber,
      'email': email,
      'consent_status': consentStatus,
      'consented_at': consentedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  EmergencyContactModel copyWith({
    String? id,
    String? userId,
    String? contactName,
    String? phoneNumber,
    String? email,
    String? consentStatus,
    DateTime? consentedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyContactModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      contactName: contactName ?? this.contactName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      consentStatus: consentStatus ?? this.consentStatus,
      consentedAt: consentedAt ?? this.consentedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
