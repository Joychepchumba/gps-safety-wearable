import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
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

    if (_isEnabled) {
      await _initSpeech();
      if (_isInitialized) {
        startListening();
      }
    }
  }

  Future<bool> _initSpeech() async {
    if (_isInitialized) return true;

    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final res = await Permission.microphone.request();
        if (!res.isGranted) {
          debugPrint('[VOICE] Microphone permission denied by user');
          return false;
        }
      }

      _isInitialized = await _speech.initialize(
        onError: (val) => debugPrint('[VOICE] Speech engine error: $val'),
        onStatus: (val) {
          debugPrint('[VOICE] Status: $val');
          if (val == 'done' || val == 'notListening') {
            _isListening = false;
            if (_isEnabled) {
              Future.delayed(const Duration(milliseconds: 600), () => startListening());
            }
          }
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('[VOICE] Init exception: $e');
      return false;
    }
  }

  Future<void> updateSettings({required bool enabled, required String phrase}) async {
    _isEnabled = enabled;
    _wakePhrase = phrase.trim().toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', enabled);
    await prefs.setString('voice_wake_word', _wakePhrase);

    if (enabled) {
      await _initSpeech();
      startListening();
    } else {
      stopListening();
    }
  }

  Future<void> startListening() async {
    if (!_isInitialized) {
      final ready = await _initSpeech();
      if (!ready) return;
    }
    if (_isListening) return;

    try {
      await _speech.listen(
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
      debugPrint('[VOICE] Actively listening for wake phrase: "$_wakePhrase"');
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
