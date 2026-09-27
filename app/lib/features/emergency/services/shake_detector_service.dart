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

  // Calibration parameters verified across physical Android devices (including Samsung Galaxy A-series)
  // Baseline gravity is ~9.8 m/s². A firm shake reaches 17-25 m/s².
  static const double shakeThreshold = 17.5; 
  static const int shakeCountThreshold = 3;  
  static const Duration shakeTimeWindow = Duration(milliseconds: 3000); // 3 seconds window
  static const Duration minShakeInterval = Duration(milliseconds: 250); // debounce between peaks

  StreamSubscription<AccelerometerEvent>? _subscription;
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
      _subscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (AccelerometerEvent event) {
          final double magnitude = sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );

          if (magnitude > shakeThreshold) {
            final now = DateTime.now();

            if (_lastShakeTime == null) {
              _shakeCount = 1;
              _lastShakeTime = now;
              debugPrint('📳 [SHAKE] Peak #1 detected: ${magnitude.toStringAsFixed(1)} m/s²');
            } else {
              final elapsed = now.difference(_lastShakeTime!);
              if (elapsed > minShakeInterval && elapsed < shakeTimeWindow) {
                _shakeCount++;
                _lastShakeTime = now;
                debugPrint('📳 [SHAKE] Peak #$_shakeCount detected: ${magnitude.toStringAsFixed(1)} m/s²');

                if (_shakeCount >= shakeCountThreshold) {
                  _shakeCount = 0;
                  _lastShakeTime = null;
                  _triggerShakeAlert();
                }
              } else if (elapsed >= shakeTimeWindow) {
                // Window expired, reset to first shake
                _shakeCount = 1;
                _lastShakeTime = now;
                debugPrint('📳 [SHAKE] Reset window. Peak #1: ${magnitude.toStringAsFixed(1)} m/s²');
              }
            }
          }
        },
        onError: (e) {
          debugPrint('[SHAKE] Accelerometer stream error: $e');
        },
        cancelOnError: false,
      );

      _isListening = true;
      debugPrint('[SHAKE] Accelerometer shake detection active (threshold: $shakeThreshold m/s², count: $shakeCountThreshold)');
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
    debugPrint('🚨 [SHAKE ALERT] 3 hard shakes verified! Triggering SOS countdown...');

    // Haptic vibration feedback
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 250, 100, 250, 100, 400]);
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }

    onShakeDetected?.call();
  }
}
