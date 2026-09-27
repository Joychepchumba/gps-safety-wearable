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
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      contactName: json['contact_name']?.toString() ?? 'Emergency Contact',
      phoneNumber: json['phone_number']?.toString() ?? '',
      email: json['email']?.toString(),
      consentStatus: json['consent_status']?.toString() ?? 'pending',
      consentedAt: json['consented_at'] != null ? DateTime.tryParse(json['consented_at'].toString()) : null,
      createdAt: json['created_at'] != null ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()) : DateTime.now(),
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
