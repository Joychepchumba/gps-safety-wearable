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

  Future<void> showForegroundMonitoringNotification({bool voiceEnabled = true, bool shakeEnabled = true}) async {
    final List<String> activeFeatures = [];
    if (voiceEnabled) activeFeatures.add("Voice SOS");
    if (shakeEnabled) activeFeatures.add("Shake SOS");
    final activeStr = activeFeatures.isNotEmpty ? activeFeatures.join(" & ") : "Standby";

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safeguard_foreground_channel',
      'SafeGuard Active Protection',
      channelDescription: 'Keeps Voice & Shake emergency detection running in the background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 999,
      title: 'SafeGuard Active Protection',
      body: 'Monitoring in background: $activeStr',
      notificationDetails: details,
    );
  }

  Future<void> cancelForegroundMonitoring() async {
    await _plugin.cancel(id: 999);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
