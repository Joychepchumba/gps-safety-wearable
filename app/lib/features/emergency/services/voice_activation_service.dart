import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

typedef OnWakeWordDetectedCallback = void Function();

class VoiceActivationService {
  static final VoiceActivationService instance = VoiceActivationService._internal();
  VoiceActivationService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isEnabled = false;
  String _wakePhrase = 'tuma msaada';

  OnWakeWordDetectedCallback? onWakeWordDetected;

  bool get isListening => _isListening;
  bool get isEnabled => _isEnabled;
  String get wakePhrase => _wakePhrase;

  Future<void> init({OnWakeWordDetectedCallback? onDetected}) async {
    if (onDetected != null) {
      onWakeWordDetected = onDetected;
    }

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? false;
    _wakePhrase = prefs.getString('voice_wake_word') ?? 'tuma msaada';

    try {
      _isInitialized = await _speech.initialize(
        onError: (val) => debugPrint('[VOICE] Speech error: $val'),
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            _isListening = false;
            // Auto restart if still enabled
            if (_isEnabled) {
              Future.delayed(const Duration(milliseconds: 500), () => startListening());
            }
          }
        },
      );

      if (_isEnabled && _isInitialized) {
        startListening();
      }
    } catch (e) {
      debugPrint('[VOICE] Init error: $e');
    }
  }

  Future<void> updateSettings({required bool enabled, required String phrase}) async {
    _isEnabled = enabled;
    _wakePhrase = phrase.trim().toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', enabled);
    await prefs.setString('voice_wake_word', _wakePhrase);

    if (enabled) {
      startListening();
    } else {
      stopListening();
    }
  }

  void startListening() {
    if (!_isInitialized || _isListening) return;

    try {
      _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase();
          debugPrint('[VOICE] Heard: "$words" (target: "$_wakePhrase")');

          if (words.contains(_wakePhrase) || _matchesWakePhrase(words)) {
            debugPrint('🎙️ [VOICE ALERT] Wake phrase confirmed! Triggering emergency...');
            _speech.stop();
            _isListening = false;
            onWakeWordDetected?.call();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
      _isListening = true;
      debugPrint('[VOICE] Listening for wake phrase: "$_wakePhrase"');
    } catch (e) {
      debugPrint('[VOICE] Listen error: $e');
    }
  }

  void stopListening() {
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
  }

  bool _matchesWakePhrase(String heard) {
    final targets = _wakePhrase.split(' ');
    int matched = 0;
    for (final t in targets) {
      if (t.isNotEmpty && heard.contains(t)) matched++;
    }
    return matched >= targets.length && targets.isNotEmpty;
  }
}
