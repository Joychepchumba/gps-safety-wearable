import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

typedef OnShakeDetectedCallback = void Function();

class ShakeDetectorService {
  static final ShakeDetectorService instance = ShakeDetectorService._internal();
  ShakeDetectorService._internal();

  // Calibration parameters verified in Lindana
  static const double shakeThreshold = 22.0; // 22 m/s² (~2.2G) requires intentional, rigorous shake
  static const int shakeCountThreshold = 3;  // 3 distinct shakes needed
  static const Duration shakeTimeWindow = Duration(milliseconds: 2000); // within 2 seconds

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  bool _isListening = false;
  bool _isEnabled = true;

  OnShakeDetectedCallback? onShakeDetected;

  bool get isListening => _isListening;
  bool get isEnabled => _isEnabled;

  Future<void> init({OnShakeDetectedCallback? onDetected}) async {
    if (onDetected != null) {
      onShakeDetected = onDetected;
    }
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('shake_detection_enabled') ?? true;

    if (_isEnabled) {
      startListening();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shake_detection_enabled', enabled);

    if (enabled) {
      startListening();
    } else {
      stopListening();
    }
  }

  void startListening() {
    if (_isListening) return;

    try {
      _subscription = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) {
          final double magnitude = sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );

          if (magnitude > shakeThreshold) {
            final now = DateTime.now();

            if (_lastShakeTime == null || now.difference(_lastShakeTime!) < shakeTimeWindow) {
              _shakeCount++;
              _lastShakeTime = now;

              if (_shakeCount >= shakeCountThreshold) {
                _shakeCount = 0;
                _lastShakeTime = null;
                _triggerShakeAlert();
              }
            } else {
              // Reset window
              _shakeCount = 1;
              _lastShakeTime = now;
            }
          }
        },
        onError: (e) {
          debugPrint('[SHAKE] Accelerometer stream error: $e');
        },
        cancelOnError: false,
      );

      _isListening = true;
      debugPrint('[SHAKE] Shake detection active (threshold: $shakeThreshold m/s², count: $shakeCountThreshold)');
    } catch (e) {
      debugPrint('[SHAKE] Failed to start shake listener: $e');
    }
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    _shakeCount = 0;
    _lastShakeTime = null;
    debugPrint('[SHAKE] Shake detection stopped.');
  }

  Future<void> _triggerShakeAlert() async {
    debugPrint('🚨 [SHAKE ALERT] 3 hard shakes detected! Triggering SOS countdown...');

    // Haptic feedback
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 300]);
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }

    onShakeDetected?.call();
  }
}
