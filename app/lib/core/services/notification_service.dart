import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../navigation/navigation_service.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String emergencyChannelId = 'safelink_emergency_popup_v2';
  static const String emergencyChannelName = 'SafeLink Emergency SOS Popups';
  static const String emergencyChannelDesc =
      'High-priority pop-up banner notifications when an emergency SOS is triggered or sent';

  Future<void> initialize() async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initSettings =
        InitializationSettings(android: initAndroid, iOS: initIOS);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[NotificationService] Notification tapped: ${response.payload}');
        final route = (response.payload != null && response.payload!.isNotEmpty)
            ? response.payload!
            : '/emergency';
        try {
          NavigationService.pushNamed(route);
        } catch (_) {}
      },
    );

    // Create high-importance channel on Android for guaranteed Heads-Up Pop-Up banner display
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final channel = AndroidNotificationChannel(
          emergencyChannelId,
          emergencyChannelName,
          description: emergencyChannelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
          showBadge: true,
        );
        await androidPlugin.createNotificationChannel(channel);
        try {
          await androidPlugin.requestNotificationsPermission();
        } catch (_) {}
      }
    }
  }

  /// Displays an urgent Heads-Up Pop-Up banner notification.
  /// This will pop up on top of any active screen (home, games, other apps, lock screen).
  Future<void> showEmergencyPopup({
    required String title,
    required String body,
    int id = 100,
    String payload = '/emergency',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      emergencyChannelId,
      emergencyChannelName,
      channelDescription: emergencyChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: 'EMERGENCY SOS ALERT',
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      color: const Color(0xFFDC2626),
      colorized: true,
      ongoing: false,
      autoCancel: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Immediate notification shown when a Voice Keyword is recognized
  Future<void> showVoiceKeywordDetectedPopup({
    required String keyword,
    required String heardText,
    bool testOnly = false,
  }) async {
    await showEmergencyPopup(
      id: 105,
      title: testOnly
          ? '🎙️ Voice Keyword Recognized: "$keyword"'
          : '🚨 VOICE SOS KEYWORD DETECTED: "$keyword"',
      body: testOnly
          ? 'Heard "$heardText" — Matched emergency phrase "$keyword".'
          : 'Heard "$heardText" — Matched "$keyword"! Starting Emergency SOS countdown.',
      payload: testOnly ? '/voice-settings' : '/emergency',
    );
  }

  /// Pop-up notification shown immediately when emergency SOS is triggered (Voice or Shake)
  Future<void> showTriggerPopup({
    required String method,
    int countdownSeconds = 10,
    String? detectedPhrase,
  }) async {
    final phraseDetail = (detectedPhrase != null && detectedPhrase.isNotEmpty)
        ? ' ("$detectedPhrase")'
        : '';
    await showEmergencyPopup(
      id: 101,
      title: '🚨 EMERGENCY SOS TRIGGERED ($method)',
      body:
          'Emergency detected via $method$phraseDetail! Dispatching SOS & live GPS in ${countdownSeconds}s. Tap to open or cancel.',
    );
  }

  /// Pop-up notification shown immediately when emergency alert is sent/dispatched
  Future<void> showDispatchedPopup({
    required String method,
    int contactsCount = 0,
  }) async {
    final destination = contactsCount > 0
        ? 'to $contactsCount emergency contacts, community responders & police'
        : 'to emergency response network & nearby BLE responders';
    await showEmergencyPopup(
      id: 102,
      title: '🚨 EMERGENCY ALERT SENT!',
      body: 'SOS dispatched via $method $destination! Live 3D GPS & BLE beacon active.',
    );
  }

  /// Urgent notification when a nearby user in distress is detected over BLE or Cloud
  Future<void> showCommunityDistressPopup({
    required String victimName,
    required double distanceMeters,
    required String sourceLabel,
  }) async {
    final distStr = distanceMeters < 1000
        ? '${distanceMeters.round()}m away'
        : '${(distanceMeters / 1000).toStringAsFixed(1)}km away';
    await showEmergencyPopup(
      id: 108,
      title: '🆘 DISTRESS SIGNAL NEARBY ($distStr)',
      body: '$victimName needs emergency assistance ($sourceLabel). Tap to view location & respond.',
      payload: '/community-responders',
    );
  }

  /// Backwards-compatible method for existing callers
  Future<void> showEmergencyAlert(String title, String body) async {
    await showEmergencyPopup(title: title, body: body, id: 100);
  }

  Future<void> cancelTriggerPopup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(id: 101);
  }

  Future<void> cancelEmergencyPopup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(id: 101);
    await _plugin.cancel(id: 102);
  }

  Future<void> showResponderAlert(String userName, double distanceKm) async {
    await showCommunityDistressPopup(
      victimName: userName,
      distanceMeters: distanceKm * 1000,
      sourceLabel: 'Community SOS Network',
    );
  }

  Future<void> showForegroundMonitoringNotification({
    bool voiceEnabled = true,
    bool shakeEnabled = true,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final List<String> activeFeatures = [];
    if (voiceEnabled) activeFeatures.add("Voice SOS");
    if (shakeEnabled) activeFeatures.add("Shake SOS");
    final activeStr = activeFeatures.isNotEmpty ? activeFeatures.join(" & ") : "Standby";

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safeguard_foreground_channel',
      'SafeGuard Active Protection',
      channelDescription: 'Keeps Voice & Shake emergency detection running in the background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 999,
      title: 'SafeGuard Active Protection',
      body: 'Monitoring in background: $activeStr',
      notificationDetails: details,
    );
  }

  Future<void> cancelForegroundMonitoring() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(id: 999);
  }

  Future<void> cancelAll() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancelAll();
  }
}
