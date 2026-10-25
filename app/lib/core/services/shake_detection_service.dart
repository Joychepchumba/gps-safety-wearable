import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

class ShakeDetectionService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  VoidCallback? onShakeDetected;

  bool _isListening = false;
  bool get isListening => _isListening;

  // Configuration
  double shakeThresholdGravity = 2.5; // ~2.5g
  int minShakeCount = 2; // At least 2 quick shakes
  int shakeWindowMs = 1200; // Within 1.2 seconds
  int debounceBetweenPeaksMs = 150; // 150ms between directional peaks

  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  DateTime? _lastPeakTime;

  void start({VoidCallback? onShake}) {
    if (onShake != null) {
      onShakeDetected = onShake;
    }

    if (_isListening) return;

    _isListening = true;
    _shakeCount = 0;
    _lastShakeTime = null;
    _lastPeakTime = null;

    try {
      // Use uiInterval (~15Hz / 66ms) instead of gameInterval (~50Hz / 20ms)
      // to reduce CPU wakeups and power draw by >70% while reliably catching human shakes.
      _accelerometerSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
        (AccelerometerEvent event) {
          _processAccelerometerEvent(event);
        },
        onError: (err) {
          debugPrint('[ShakeDetectionService] Accelerometer stream error: $err');
        },
        cancelOnError: false,
      );
      debugPrint('[ShakeDetectionService] Shake detection armed and listening');
    } catch (e) {
      debugPrint('[ShakeDetectionService] Failed to start shake detection: $e');
      _isListening = false;
    }
  }

  void _processAccelerometerEvent(AccelerometerEvent event) {
    final now = DateTime.now();

    // Standard earth gravity constant
    const double g0 = 9.80665;
    final double gX = event.x / g0;
    final double gY = event.y / g0;
    final double gZ = event.z / g0;

    final double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

    if (gForce >= shakeThresholdGravity) {
      // Check debounce between consecutive peaks
      if (_lastPeakTime != null &&
          now.difference(_lastPeakTime!).inMilliseconds < debounceBetweenPeaksMs) {
        return;
      }

      _lastPeakTime = now;

      // Reset count if window expired
      if (_lastShakeTime != null &&
          now.difference(_lastShakeTime!).inMilliseconds > shakeWindowMs) {
        _shakeCount = 0;
      }

      _lastShakeTime = now;
      _shakeCount++;

      debugPrint('[ShakeDetectionService] Peak detected! gForce=${gForce.toStringAsFixed(2)}, count=$_shakeCount/$minShakeCount');

      if (_shakeCount >= minShakeCount) {
        _shakeCount = 0;
        _triggerShakeAlert();
      }
    }
  }

  Future<void> _triggerShakeAlert() async {
    debugPrint('[ShakeDetectionService] SHAKE DETECTED -> Triggering Emergency SOS!');

    // Provide immediate haptic feedback
    try {
      HapticFeedback.heavyImpact();
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 250, 100, 350]);
      }
    } catch (_) {}

    onShakeDetected?.call();
  }

  void stop() {
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _isListening = false;
    _shakeCount = 0;
    debugPrint('[ShakeDetectionService] Shake detection stopped');
  }

  /// Manually simulate or test a shake event (useful for testing or direct button trigger)
  void simulateShake() {
    _triggerShakeAlert();
  }
}
