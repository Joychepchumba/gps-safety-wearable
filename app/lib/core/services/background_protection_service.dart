import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry point required by flutter_foreground_task. The detectors themselves
/// (shake + voice) run in the main isolate, which this service keeps alive,
/// so the task handler only needs to exist.
@pragma('vm:entry-point')
void backgroundProtectionCallback() {
  FlutterForegroundTask.setTaskHandler(_ProtectionTaskHandler());
}

class _ProtectionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps SafeLink's emergency detectors running while the app is in the
/// background (home button, other app in front, screen off).
///
/// Android only allows continuous microphone / sensor / location access in the
/// background when a foreground service of the matching type is running, and
/// that service must be started while the app is visible.
class BackgroundProtectionService {
  static const int _serviceId = 4242;
  static bool _initialised = false;

  static void init() {
    if (!Platform.isAndroid || _initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safeguard_protection',
        channelName: 'SafeLink Active Protection',
        channelDescription:
            'Keeps Shake and Voice emergency detection running in the background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Boot-time start is blocked by Android 15 for microphone services.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        // Partial wake lock: lets the accelerometer + recorder keep running
        // when the screen is off.
        allowWakeLock: true,
        allowWifiLock: false, // Disabled persistent Wi-Fi lock to prevent excessive standby battery drain
      ),
    );
    _initialised = true;
  }

  /// Asks for the permissions the background service needs and starts it.
  /// Returns true when the service is running afterwards.
  static Future<bool> start({
    required bool voiceEnabled,
    required bool shakeEnabled,
  }) async {
    if (!Platform.isAndroid) return false;
    init();

    try {
      // Notification permission (Android 13+) - the service notification.
      final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
      if (notifPerm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      // Runtime requirements for each foreground service type.
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

      // Keep Android's battery optimiser from killing the service.
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // "Display over other apps" lets the SOS screen open from the background.
      // Asked only once so the user is not nagged on every launch.
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
        // Android 14+ requires at least one declared type whose runtime
        // permission is granted; without mic/location there is nothing to keep alive.
        debugPrint('[BackgroundProtection] Microphone and location permission denied - service not started');
        return false;
      }

      final text = _statusText(voiceEnabled: voiceEnabled, shakeEnabled: shakeEnabled);

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'SafeLink protection active',
          notificationText: text,
        );
        return true;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: types,
        notificationTitle: 'SafeLink protection active',
        notificationText: text,
        notificationInitialRoute: '/home',
        callback: backgroundProtectionCallback,
      );
      final ok = result is ServiceRequestSuccess;
      debugPrint('[BackgroundProtection] start -> $result (types: ${types.map((t) => t.rawValue).toList()})');
      return ok;
    } catch (e) {
      debugPrint('[BackgroundProtection] start failed: $e');
      return false;
    }
  }

  /// Refreshes the notification text when the user toggles Shake / Voice.
  static Future<void> updateStatus({
    required bool voiceEnabled,
    required bool shakeEnabled,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'SafeLink protection active',
          notificationText: _statusText(voiceEnabled: voiceEnabled, shakeEnabled: shakeEnabled),
        );
      }
    } catch (_) {}
  }

  /// Displays an urgent foreground alert notification indicating an SOS has been dispatched!
  static Future<void> notifyAlertDispatched(String method, {int contactsCount = 0}) async {
    if (!Platform.isAndroid) return;
    try {
      final methodStr = method == 'voice_keyword'
          ? 'Voice Keyword'
          : (method == 'app_shake' ? 'Emergency Shake' : 'Emergency Button');
      final text = contactsCount > 0
          ? '🚨 SOS Dispatched via $methodStr! Alert & Live GPS sent to $contactsCount emergency contacts.'
          : '🚨 SOS Dispatched via $methodStr! Live 3D GPS tracking active.';

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: '🚨 EMERGENCY ALERT SENT',
          notificationText: text,
        );
      }
    } catch (e) {
      debugPrint('[BackgroundProtection] notifyAlertDispatched error: $e');
    }
  }

  /// Brings the app to the foreground (used when an SOS is triggered while the
  /// app is minimised). Best-effort: needs "display over other apps" on some
  /// Android versions.
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
