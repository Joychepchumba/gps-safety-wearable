import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/di/service_locator.dart';
import '../../../core/navigation/navigation_service.dart';
import '../../../core/services/background_protection_service.dart';
import '../../../core/services/notification_service.dart';

typedef OnWakeWordDetectedCallback = void Function();
typedef BackgroundVoiceService = VoiceActivationService;

/// Voice Activation & Background Voice Service based directly on the
/// Lindana baseline (`f719c882427d46639e537aeee611f0979bc51aa4`):
///
/// - Uses a 2+ word user-configured wake phrase (default `'tuma msaada'`).
/// - Listens in 10-second windows (`listenFor: 10s`, `pauseFor: 4s`,
///   `cancelOnError: true`) with no hardcoded `localeId` in background mode so
///   the device language works seamlessly for both Kiswahili and English.
/// - Checks only on `result.finalResult` using `_phraseDetected(spoken, phrase)`
///   (`spoken.contains(phrase)` or all words of the 2+ word phrase present),
///   preventing accidental triggers from partial speech hypotheses.
/// - Can be stopped (`stop()` / `pause()`) when opening `VoiceActivationPage`
///   ("FREEDOM FOR THE MIC") or during active panic mode, and resumed
///   (`startIfEnabled()` / `resume()`) when leaving `VoiceActivationPage`.
class VoiceActivationService with WidgetsBindingObserver {
  static final VoiceActivationService instance =
      VoiceActivationService._internal();

  VoiceActivationService._internal() {
    try {
      WidgetsBinding.instance.addObserver(this);
      FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    } catch (_) {}
  }

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _isListening = false;
  bool _wantListening = false;
  bool _isEnabled = false;
  bool _isPausedForConfigOrPanic = false;
  String _wakePhrase = 'tuma msaada';

  DateTime? _lastTriggerAt;
  static const Duration _triggerCooldown = Duration(seconds: 10);

  OnWakeWordDetectedCallback? onWakeWordDetected;

  final ValueNotifier<String> lastHeardWords = ValueNotifier<String>('');
  final ValueNotifier<String?> lastDetectedKeyword = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<DateTime?> lastDetectedAt = ValueNotifier<DateTime?>(
    null,
  );
  final ValueNotifier<bool> isTranscribing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isListeningNotifier = ValueNotifier<bool>(false);

  bool get isListening => _isListening || _speech.isListening;
  bool get isEnabled => _isEnabled;
  String get wakePhrase => _wakePhrase;

  // ── 5-second watchdog callback from FlutterForegroundTask ─────────────────
  void _onForegroundTaskData(Object data) {
    if (data == 'WATCHDOG_TICK') {
      if (_isEnabled && _wantListening && !_isPausedForConfigOrPanic && !_isListening) {
        _listen();
      }
    } else if (data == 'ALERT_PHRASE_DETECTED') {
      onWakeWordDetected?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isEnabled || _isPausedForConfigOrPanic) return;
    if (state == AppLifecycleState.resumed) {
      if (_wantListening && !_isListening) {
        Future.delayed(const Duration(milliseconds: 300), _listen);
      }
    }
  }

  /// Call this whenever contacts are loaded so background preferences stay synced.
  static Future<void> saveContactsForBackground(
    List<Map<String, dynamic>> contacts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_contacts_json', jsonEncode(contacts));
  }

  /// Call this whenever GPS position updates.
  static Future<void> savePositionForBackground(
    double lat,
    double lng,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_known_lat', lat);
    await prefs.setDouble('last_known_lng', lng);
  }

  /// Loads saved voice settings from SharedPreferences.
  Future<void> init({OnWakeWordDetectedCallback? onDetected}) async {
    if (onDetected != null) {
      onWakeWordDetected = onDetected;
    }
    await _reloadPrefs();
  }

  Future<void> _reloadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? false;
    _wakePhrase = (prefs.getString('voice_wake_word') ?? 'tuma msaada').trim();
    if (_wakePhrase.isEmpty) {
      _wakePhrase = 'tuma msaada';
    }
  }

  Future<void> updateSettings({
    required bool enabled,
    required String phrase,
    bool startImmediately = true,
  }) async {
    _isEnabled = enabled;
    _wakePhrase = phrase.trim().isNotEmpty ? phrase.trim() : 'tuma msaada';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', _isEnabled);
    await prefs.setString('voice_wake_word', _wakePhrase);

    await BackgroundProtectionService.updateStatus(
      voiceEnabled: _isEnabled,
      shakeEnabled: true,
      wakePhrase: _wakePhrase,
    );

    if (!startImmediately) return;

    if (_isEnabled) {
      await startIfEnabled();
    } else {
      await stop();
    }
  }

  Future<void> updateWakeWord(String newPhrase) async {
    _wakePhrase = newPhrase.trim().isNotEmpty ? newPhrase.trim() : 'tuma msaada';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_wake_word', _wakePhrase);
    await BackgroundProtectionService.updateStatus(
      voiceEnabled: _isEnabled,
      shakeEnabled: true,
      wakePhrase: _wakePhrase,
    );
  }

  Future<bool> _ensureMicPermission() async {
    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Starts background voice monitoring if `voice_activation_enabled` is true.
  /// Matches `BackgroundVoiceService.instance.startIfEnabled()` from Lindana `f719c88`.
  Future<void> startIfEnabled() async {
    await _reloadPrefs();
    if (!_isEnabled) return;

    if (!await _ensureMicPermission()) return;

    _isPausedForConfigOrPanic = false;
    _wantListening = true;

    await BackgroundProtectionService.start(
      voiceEnabled: true,
      shakeEnabled: true,
      wakePhrase: _wakePhrase,
    );

    if (!_isListening) {
      await _listen();
    }
  }

  Future<void> startListening() => startIfEnabled();

  /// Stops voice recognition so `VoiceActivationPage` has exclusive access to
  /// the microphone ("FREEDOM FOR THE MIC") or when disabled.
  Future<void> stop() async {
    _isPausedForConfigOrPanic = true;
    _wantListening = false;
    _isListening = false;
    isListeningNotifier.value = false;
    isTranscribing.value = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  void stopListening() {
    unawaited(stop());
  }

  Future<void> pause() => stop();
  Future<void> resume() => startIfEnabled();

  // ── Speech loop (Exact Lindana f719c88 _VoiceTaskHandler._listen logic) ───
  Future<void> _listen() async {
    if (!_wantListening || _isPausedForConfigOrPanic || !_isEnabled) return;

    if (!_initialized) {
      try {
        _initialized = await _speech.initialize(
          onStatus: (status) {
            if (status == 'listening') {
              _isListening = true;
              isListeningNotifier.value = true;
              isTranscribing.value = true;
            } else if (status == 'done' || status == 'notListening') {
              _isListening = false;
              isListeningNotifier.value = false;
              isTranscribing.value = false;
              if (_wantListening && !_isPausedForConfigOrPanic && _isEnabled) {
                Future.delayed(const Duration(milliseconds: 500), _listen);
              }
            }
          },
          onError: (_) {
            _isListening = false;
            isListeningNotifier.value = false;
            isTranscribing.value = false;
            if (_wantListening && !_isPausedForConfigOrPanic && _isEnabled) {
              Future.delayed(const Duration(seconds: 3), _listen);
            }
          },
        );
      } catch (_) {
        _initialized = false;
      }
    }

    if (!_initialized || !_wantListening || _isPausedForConfigOrPanic) return;
    if (_speech.isListening) return;

    _isListening = true;
    isListeningNotifier.value = true;
    isTranscribing.value = true;

    try {
      await _speech.listen(
        onResult: (result) async {
          lastHeardWords.value = result.recognizedWords;
          if (result.finalResult) {
            _isListening = false;
            isTranscribing.value = false;
            final spoken = result.recognizedWords.toLowerCase().trim();
            final phrase = _wakePhrase.toLowerCase().trim();
            if (_phraseDetected(spoken, phrase)) {
              await _handleDetected(spoken);
            }
            if (_wantListening && !_isPausedForConfigOrPanic && _isEnabled) {
              Future.delayed(const Duration(milliseconds: 300), _listen);
            }
          }
        },
        // No localeId — uses the device's configured language.
        // ignore: deprecated_member_use
        listenFor: const Duration(seconds: 10),
        // ignore: deprecated_member_use
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
        ),
      );
    } catch (_) {
      _isListening = false;
      isListeningNotifier.value = false;
      isTranscribing.value = false;
      if (_wantListening && !_isPausedForConfigOrPanic && _isEnabled) {
        Future.delayed(const Duration(seconds: 3), _listen);
      }
    }
  }

  /// Exact Lindana `f719c88` wake phrase detector:
  /// Matches if `spoken` contains the full `phrase`, or if `phrase` has >= 2 words
  /// and every word in `phrase` appears in `spoken`.
  bool _phraseDetected(String spoken, String phrase) {
    if (spoken.isEmpty || phrase.isEmpty) return false;
    if (spoken.contains(phrase)) return true;
    final words = phrase
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 2) return false;
    return words.every((w) => spoken.contains(w));
  }

  bool matchesWakePhrase(String heard, {String? customPhrase}) {
    final spoken = heard.toLowerCase().trim();
    final target = (customPhrase ?? _wakePhrase).toLowerCase().trim();
    return _phraseDetected(spoken, target);
  }

  String? findMatchedKeyword(String heard) {
    if (matchesWakePhrase(heard)) {
      return _wakePhrase;
    }
    return null;
  }

  Future<void> _handleDetected(String heardText) async {
    final now = DateTime.now();
    if (_lastTriggerAt != null &&
        now.difference(_lastTriggerAt!) < _triggerCooldown) {
      return;
    }
    _lastTriggerAt = now;

    lastDetectedKeyword.value = _wakePhrase;
    lastDetectedAt.value = now;

    // Auto-clear lastDetectedKeyword after 10s
    Future.delayed(const Duration(seconds: 10), () {
      if (lastDetectedAt.value == now) {
        lastDetectedKeyword.value = null;
      }
    });

    // 1. Show local notification ("📩 Alert Sent via Voice")
    await _showLocalNotification();

    // 2. Fire callback to dispatch silent SMS/Supabase alert & show VoiceAlertDialog
    onWakeWordDetected?.call();
  }

  /// Simulates voice phrase detection (for demo/testing)
  void simulateVoiceDetected({String? simulatedPhrase}) {
    final phrase = simulatedPhrase ?? _wakePhrase;
    lastHeardWords.value = phrase;
    unawaited(_handleDetected(phrase));
  }

  Future<void> _showLocalNotification() async {
    try {
      await sl<NotificationService>().showEmergencyPopup(
        id: 998,
        title: '📩 Alert Sent via Voice',
        body: 'Your emergency contacts have been notified. Help is on the way.',
        payload: '/home',
      );
    } catch (_) {
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        await plugin.show(
          id: 998,
          title: '📩 Alert Sent via Voice',
          body: 'Your emergency contacts have been notified. Help is on the way.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'lindana_emergency_v2',
              'Emergency Alerts',
              channelDescription: 'Voice phrase triggered emergency alert',
              importance: Importance.max,
              priority: Priority.high,
              fullScreenIntent: true,
              playSound: true,
              enableVibration: true,
            ),
          ),
        );
      } catch (_) {}
    }
  }

  /// Shows the Lindana `📩 ALERT SENT` confirmation dialog when wake phrase fires.
  static void showVoiceAlertSentDialog() {
    final ctx = NavigationService.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showGeneralDialog(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      pageBuilder: (dialogCtx, _, _) => const VoiceAlertSentDialog(),
      transitionBuilder: (dialogCtx, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}

/// Exact Lindana `f719c88` `_HomeVoiceAlertDialog` / `_VoiceAlertDialog`:
/// Shown in-app when the wake phrase is detected and silent SMS alert is sent.
class VoiceAlertSentDialog extends StatefulWidget {
  const VoiceAlertSentDialog({super.key});

  @override
  State<VoiceAlertSentDialog> createState() => _VoiceAlertSentDialogState();
}

class _VoiceAlertSentDialogState extends State<VoiceAlertSentDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _auto;
  int _count = 10;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _auto = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _count--);
      if (_count <= 0) {
        t.cancel();
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _auto?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A6B8A), Color(0xFF4FABCB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4FABCB).withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, _) => Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '📩 ALERT SENT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Wake phrase detected. SMS sent to your emergency contacts.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your location was included in the alert.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _dismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1A6B8A),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'OK — Dismiss ($_count)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
