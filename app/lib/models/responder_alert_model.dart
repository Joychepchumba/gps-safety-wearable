class ResponderAlertModel {
  final String id;
  final String panicEventId;
  final String responderId;
  final DateTime alertedAt;
  final DateTime? acknowledgedAt;
  final DateTime? arrivedAt;
  final double distanceM;

  ResponderAlertModel({
    required this.id,
    required this.panicEventId,
    required this.responderId,
    required this.alertedAt,
    this.acknowledgedAt,
    this.arrivedAt,
    required this.distanceM,
  });

  factory ResponderAlertModel.fromJson(Map<String, dynamic> json) {
    return ResponderAlertModel(
      id: json['id'],
      panicEventId: json['panic_event_id'],
      responderId: json['responder_id'],
      alertedAt: DateTime.parse(json['alerted_at']),
      acknowledgedAt: json['acknowledged_at'] != null ? DateTime.parse(json['acknowledged_at']) : null,
      arrivedAt: json['arrived_at'] != null ? DateTime.parse(json['arrived_at']) : null,
      distanceM: json['distance_m']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'panic_event_id': panicEventId,
      'responder_id': responderId,
      'alerted_at': alertedAt.toIso8601String(),
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
      'arrived_at': arrivedAt?.toIso8601String(),
      'distance_m': distanceM,
    };
  }

  ResponderAlertModel copyWith({
    String? id,
    String? panicEventId,
    String? responderId,
    DateTime? alertedAt,
    DateTime? acknowledgedAt,
    DateTime? arrivedAt,
    double? distanceM,
  }) {
    return ResponderAlertModel(
      id: id ?? this.id,
      panicEventId: panicEventId ?? this.panicEventId,
      responderId: responderId ?? this.responderId,
      alertedAt: alertedAt ?? this.alertedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      distanceM: distanceM ?? this.distanceM,
    );
  }
}
