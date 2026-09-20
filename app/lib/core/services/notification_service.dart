import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIOS =
        DarwinInitializationSettings();
    const InitializationSettings initSettings =
        InitializationSettings(android: initAndroid, iOS: initIOS);
    await _plugin.initialize(settings: initSettings);
  }

  Future<void> showEmergencyAlert(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> showResponderAlert(String userName, double distanceKm) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'responder_channel',
      'Responder Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 1,
      title: 'Responder Needed',
      body: '$userName is ${distanceKm.toStringAsFixed(1)}km away.',
      notificationDetails: details,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
