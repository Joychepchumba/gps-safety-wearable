class UserModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String email;
  final String? avatarUrl;
  final bool isCommunityResponder;
  final String? responderStatus;
  final DateTime? responderOptedInAt;
  final DateTime? responderOptedOutAt;
  final bool hasWearable;
  final bool hasEmergencyPassword;
  final String? pushToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    this.avatarUrl,
    required this.isCommunityResponder,
    this.responderStatus,
    this.responderOptedInAt,
    this.responderOptedOutAt,
    required this.hasWearable,
    this.hasEmergencyPassword = false,
    this.pushToken,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      email: json['email'] ?? '',
      avatarUrl: json['avatar_url'],
      isCommunityResponder: json['is_community_responder'] ?? false,
      responderStatus: json['responder_status'],
      responderOptedInAt: json['responder_opted_in_at'] != null ? DateTime.parse(json['responder_opted_in_at']) : null,
      responderOptedOutAt: json['responder_opted_out_at'] != null ? DateTime.parse(json['responder_opted_out_at']) : null,
      hasWearable: json['has_wearable'] ?? false,
      hasEmergencyPassword: json['emergency_password_hash'] != null && json['emergency_password_hash'].toString().isNotEmpty,
      pushToken: json['push_token'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'email': email,
      'avatar_url': avatarUrl,
      'is_community_responder': isCommunityResponder,
      'responder_status': responderStatus,
      'responder_opted_in_at': responderOptedInAt?.toIso8601String(),
      'responder_opted_out_at': responderOptedOutAt?.toIso8601String(),
      'has_wearable': hasWearable,
      'push_token': pushToken,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? phoneNumber,
    String? email,
    String? avatarUrl,
    bool? isCommunityResponder,
    String? responderStatus,
    DateTime? responderOptedInAt,
    DateTime? responderOptedOutAt,
    bool? hasWearable,
    String? pushToken,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isCommunityResponder: isCommunityResponder ?? this.isCommunityResponder,
      responderStatus: responderStatus ?? this.responderStatus,
      responderOptedInAt: responderOptedInAt ?? this.responderOptedInAt,
      responderOptedOutAt: responderOptedOutAt ?? this.responderOptedOutAt,
      hasWearable: hasWearable ?? this.hasWearable,
      pushToken: pushToken ?? this.pushToken,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
