import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry point required by flutter_foreground_task.
/// Emits a 5-second watchdog tick back to the main isolate (matching the
/// Lindana f719c88 BackgroundVoiceService 5000ms interval) so the speech
/// recognition loop and shake detector stay alive continuously in the background.
@pragma('vm:entry-point')
void backgroundProtectionCallback() {
  FlutterForegroundTask.setTaskHandler(_ProtectionTaskHandler());
}

class _ProtectionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain('WATCHDOG_TICK');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain('WATCHDOG_TICK');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_stop') {
      FlutterForegroundTask.stopService();
    }
  }
}

/// Keeps SafeLink's emergency detectors running while the app is in the
/// background (home button, other app in front, screen off).
class BackgroundProtectionService {
  static const int _serviceId = 4242;
  static bool _initialised = false;

  static void init() {
    if (!Platform.isAndroid || _initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lindana_voice',
        channelName: 'Lindana Voice Monitor',
        channelDescription: 'Listening for your emergency wake phrase',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Watchdog every 5 s — keeps speech loop alive (matches Lindana f719c88)
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialised = true;
  }

  /// Asks for the permissions the background service needs and starts it.
  static Future<bool> start({
    required bool voiceEnabled,
    required bool shakeEnabled,
    String? wakePhrase,
  }) async {
    if (!Platform.isAndroid) return false;
    init();

    try {
      final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
      if (notifPerm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final micGranted = (await Permission.microphone.request()).isGranted;
      var locationGranted = false;
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        locationGranted = perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always;
      } catch (_) {}

      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await FlutterForegroundTask.canDrawOverlays &&
            !(prefs.getBool('overlay_permission_asked') ?? false)) {
          await prefs.setBool('overlay_permission_asked', true);
          await FlutterForegroundTask.openSystemAlertWindowSettings();
        }
      } catch (_) {}

      final types = <ForegroundServiceTypes>[
        if (micGranted) ForegroundServiceTypes.microphone,
        if (locationGranted) ForegroundServiceTypes.location,
      ];
      if (types.isEmpty) {
        debugPrint(
          '[BackgroundProtection] Microphone and location permission denied - service not started',
        );
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final phrase = wakePhrase ?? prefs.getString('voice_wake_word') ?? 'tuma msaada';
      final title = voiceEnabled ? 'SafeLink is listening' : 'SafeLink protection active';
      final text = voiceEnabled
          ? 'Say "$phrase" to send a silent alert'
          : _statusText(voiceEnabled: voiceEnabled, shakeEnabled: shakeEnabled);

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return true;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: types,
        notificationTitle: title,
        notificationText: text,
        notificationInitialRoute: '/home',
        callback: backgroundProtectionCallback,
      );
      final ok = result is ServiceRequestSuccess;
      debugPrint(
        '[BackgroundProtection] start -> $result (types: ${types.map((t) => t.rawValue).toList()})',
      );
      return ok;
    } catch (e) {
      debugPrint('[BackgroundProtection] start failed: $e');
      return false;
    }
  }

  /// Refreshes the notification text when the user toggles Shake / Voice or updates wake word.
  static Future<void> updateStatus({
    required bool voiceEnabled,
    required bool shakeEnabled,
    String? wakePhrase,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        final prefs = await SharedPreferences.getInstance();
        final phrase = wakePhrase ?? prefs.getString('voice_wake_word') ?? 'tuma msaada';
        final title = voiceEnabled ? 'SafeLink is listening' : 'SafeLink protection active';
        final text = voiceEnabled
            ? 'Say "$phrase" to send a silent alert'
            : _statusText(voiceEnabled: voiceEnabled, shakeEnabled: shakeEnabled);
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  /// Displays an urgent foreground alert notification indicating an SOS has been dispatched.
  static Future<void> notifyAlertDispatched(String method, {int contactsCount = 0}) async {
    if (!Platform.isAndroid) return;
    try {
      final methodStr = method == 'voice_keyword' || method == 'app_voice'
          ? 'Voice Keyword'
          : (method == 'app_shake' ? 'Emergency Shake' : 'Emergency Button');
      final text = contactsCount > 0
          ? '📩 Alert Sent via $methodStr! Your $contactsCount emergency contacts have been notified.'
          : '📩 Alert Sent via $methodStr! Your emergency contacts have been notified.';

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: '📩 Alert Sent via Voice',
          notificationText: text,
        );
      }
    } catch (e) {
      debugPrint('[BackgroundProtection] notifyAlertDispatched error: $e');
    }
  }

  static Future<void> bringToFront({String route = '/emergency'}) async {
    if (!Platform.isAndroid) return;
    try {
      FlutterForegroundTask.wakeUpScreen();
      FlutterForegroundTask.launchApp(route);
    } catch (e) {
      debugPrint('[BackgroundProtection] bringToFront failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  static String _statusText({required bool voiceEnabled, required bool shakeEnabled}) {
    final parts = <String>[
      if (shakeEnabled) 'Shake SOS on',
      if (voiceEnabled) 'Voice SOS on',
    ];
    return parts.isEmpty ? 'Standby' : parts.join(' • ');
  }
}
