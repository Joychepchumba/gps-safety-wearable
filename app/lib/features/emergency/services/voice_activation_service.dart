import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/constants/app_constants.dart';

typedef OnWakeWordDetectedCallback = void Function();

/// Dual-Engine Voice SOS Detection:
///
/// 1. PRIMARY ENGINE: On-Device Speech Recognizer (Google Speech Services / native STT).
///    Runs real-time speech recognition on-device with zero network latency.
///    Recognizes both English ("help", "emergency", "save me", "call police")
///    and Kiswahili ("msaada", "tuma msaada", "nisaidie", "piga polisi") plus custom phrases.
///
/// 2. SECONDARY ENGINE: Audio Chunk Recording + Whisper Model.
///    If the device lacks Google Speech Services or on-device STT fails, samples audio
///    chunks with sensitive -50 dB threshold and uploads to `/voice/detect`.
class VoiceActivationService {
  static final VoiceActivationService instance = VoiceActivationService._internal();
  VoiceActivationService._internal();

  // --- tuning ---------------------------------------------------------------
  static const Duration _chunkDuration = Duration(seconds: 4);
  static const Duration _ampPollInterval = Duration(milliseconds: 250);
  // Sensitive speech threshold (-50 dB ensures normal speaking voice is caught)
  static const double _speechThresholdDb = -50.0;
  static const Duration _triggerCooldown = Duration(seconds: 20);

  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _wantListening = false;
  bool _isSpeechListening = false;
  bool _usingSecondaryEngine = false;
  int _sttBusyErrorCount = 0;
  bool _isEnabled = true;
  String _wakePhrase = 'tuma msaada';

  DateTime? _lastTriggerAt;
  Timer? _sttKeepAliveTimer;

  static const List<String> defaultWakePhrases = [
    'help',
    'help me',
    'send help',
    'emergency',
    'save me',
    'call police',
    'call the police',
    'tuma msaada',
    'msaada',
    'nisaidie',
    'piga polisi',
    'okoa maisha',
  ];

  OnWakeWordDetectedCallback? onWakeWordDetected;

  bool get isListening => _wantListening;
  bool get isEnabled => _isEnabled;
  String get wakePhrase => _wakePhrase;

  /// Simulates voice phrase detection (useful for testing & demo on emulators)
  void simulateVoiceDetected() {
    debugPrint('🎙️ [VOICE SIMULATION] Simulated emergency voice trigger invoked!');
    onWakeWordDetected?.call();
  }

  /// Loads saved settings.
  Future<void> init({OnWakeWordDetectedCallback? onDetected}) async {
    if (onDetected != null) {
      onWakeWordDetected = onDetected;
    }
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? true;
    _wakePhrase = prefs.getString('voice_wake_word') ?? 'tuma msaada';
  }

  Future<void> updateSettings({required bool enabled, required String phrase}) async {
    _isEnabled = enabled;
    _wakePhrase = phrase.trim().toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', enabled);
    await prefs.setString('voice_wake_word', _wakePhrase);

    if (enabled) {
      await startListening();
    } else {
      stopListening();
    }
  }

  Future<bool> _ensureMicPermission() async {
    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        debugPrint('[VOICE] Microphone permission not granted');
      }
      return status.isGranted;
    } catch (e) {
      debugPrint('[VOICE] Permission error: $e');
      return false;
    }
  }

  Future<void> startListening() async {
    if (_wantListening) return;
    if (!await _ensureMicPermission()) return;
    _wantListening = true;
    _usingSecondaryEngine = false;
    _sttBusyErrorCount = 0;
    debugPrint('[VOICE] Starting voice safety detection...');

    // Try primary on-device native speech recognizer first
    final onDeviceOk = await _initSpeech();
    if (onDeviceOk) {
      debugPrint('[VOICE] Primary on-device native speech recognizer initialized');
      _startContinuousStt();
    } else {
      debugPrint('[VOICE] On-device STT not available; using audio chunking engine');
      _usingSecondaryEngine = true;
      unawaited(_runChunkRecordingLoop());
    }
  }

  void stopListening() {
    _wantListening = false;
    _usingSecondaryEngine = false;
    _sttKeepAliveTimer?.cancel();
    _sttKeepAliveTimer = null;
    _stopSpeechEngine();
    unawaited(_recorder.stop().catchError((_) => null));
    debugPrint('[VOICE] Voice detection stopped');
  }

  void _stopSpeechEngine() {
    try {
      _speech.stop();
    } catch (_) {}
    _isSpeechListening = false;
  }

  int _consecutiveNoMatchCount = 0;

  // --------------------------------------------------------------------------
  // PRIMARY ENGINE: Native Continuous Speech Recognition
  // --------------------------------------------------------------------------
  Future<bool> _initSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(
        onError: (err) {
          final msg = err.errorMsg;
          _isSpeechListening = false;

          // Filter repetitive ambient silence notice from log output
          if (msg != 'error_no_match') {
            debugPrint('[VOICE STT] Engine status notice: $msg');
          }

          if (msg == 'error_busy') {
            _sttBusyErrorCount++;
            if (_sttBusyErrorCount >= 3) {
              debugPrint('[VOICE STT] Mic busy repeatedly ($msg). Switching seamlessly to Whisper background engine...');
              _switchToSecondaryEngine();
              return;
            }
            _restartSttSoon(delay: const Duration(milliseconds: 2000));
          } else if (msg == 'error_speech_timeout') {
            // Ambient timeout, smoothly restart
            _restartSttSoon(delay: const Duration(milliseconds: 1000));
          } else if (msg == 'error_no_match') {
            _consecutiveNoMatchCount++;
            if (_consecutiveNoMatchCount >= 5) {
              debugPrint('[VOICE STT] Repeated empty matches ($msg) on this device. Switching seamlessly to Whisper audio chunking engine...');
              _switchToSecondaryEngine();
              return;
            }
            // Do not call _restartSttSoon here; let onStatus('done') restart cleanly
          } else {
            _restartSttSoon(delay: const Duration(milliseconds: 1500));
          }
        },
        onStatus: (status) {
          if (status == 'listening') {
            _isSpeechListening = true;
          } else if (status == 'done') {
            _isSpeechListening = false;
            // Only restart when done, ensuring recognizer lifecycle has closed
            _restartSttSoon(delay: const Duration(milliseconds: 1000));
          } else if (status == 'notListening') {
            _isSpeechListening = false;
          }
        },
      );
    } catch (e) {
      debugPrint('[VOICE STT] Initialization exception: $e');
      _speechReady = false;
    }
    return _speechReady;
  }

  void _switchToSecondaryEngine() {
    _usingSecondaryEngine = true;
    _sttKeepAliveTimer?.cancel();
    _sttKeepAliveTimer = null;
    _stopSpeechEngine();
    unawaited(_runChunkRecordingLoop());
  }

  void _restartSttSoon({Duration delay = const Duration(milliseconds: 1000)}) {
    if (!_wantListening || _usingSecondaryEngine) return;
    _sttKeepAliveTimer?.cancel();
    _sttKeepAliveTimer = Timer(delay, () {
      if (_wantListening && !_isSpeechListening && !_usingSecondaryEngine) {
        _startContinuousStt();
      }
    });
  }

  Future<void> _startContinuousStt() async {
    if (!_wantListening || _isSpeechListening || _usingSecondaryEngine) return;

    try {
      if (_speech.isListening) {
        _isSpeechListening = true;
        return;
      }
      _isSpeechListening = true;
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          _sttBusyErrorCount = 0;
          _consecutiveNoMatchCount = 0;
          debugPrint('[VOICE HEARD] "$words"');
          if (_matchesWakePhrase(words)) {
            _fireTrigger('on-device speech recognition: "$words"');
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint('[VOICE STT] Listen start notice: $e');
      _isSpeechListening = false;
      _restartSttSoon(delay: const Duration(milliseconds: 2000));
    }
  }

  // --------------------------------------------------------------------------
  // SECONDARY ENGINE: Audio Chunk Recorder (Whisper Fallback)
  // --------------------------------------------------------------------------
  Future<void> _runChunkRecordingLoop() async {
    while (_wantListening) {
      await _recordAndAnalyseChunk();
    }
  }

  Future<void> _recordAndAnalyseChunk() async {
    final path = '${Directory.systemTemp.path}/sg_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('[VOICE RECORDER] Start error: $e');
      await Future.delayed(const Duration(seconds: 2));
      return;
    }

    var peakDb = -160.0;
    final end = DateTime.now().add(_chunkDuration);
    while (_wantListening && DateTime.now().isBefore(end)) {
      await Future.delayed(_ampPollInterval);
      try {
        final amp = await _recorder.getAmplitude();
        peakDb = math.max(peakDb, amp.current);
      } catch (_) {}
    }

    String? recorded;
    try {
      recorded = await _recorder.stop();
    } catch (_) {}
    recorded ??= path;
    final file = File(recorded);

    // If quiet room with no speech, discard
    if (!_wantListening || peakDb < _speechThresholdDb) {
      _deleteQuietly(file);
      await Future.delayed(const Duration(milliseconds: 300));
      return;
    }

    // Audio detected, send to Whisper model
    unawaited(_uploadToWhisper(file));
  }

  Future<void> _uploadToWhisper(File file) async {
    try {
      final baseUrl = await AppConstants.getEffectiveBackendUrl();
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/voice/detect'))
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..fields['auto_trigger'] = 'false'
        ..fields['custom_phrase'] = _wakePhrase
        ..files.add(await http.MultipartFile.fromPath('audio', file.path, filename: 'chunk.wav'));

      final streamed = await request.send().timeout(const Duration(seconds: 12));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final transcription = (data['transcription'] ?? '').toString().toLowerCase().trim();
        debugPrint('[VOICE WHISPER] Heard: "$transcription"');
        final detected = data['emergency_detected'] == true || _matchesWakePhrase(transcription);
        if (detected) {
          _fireTrigger('backend whisper: "$transcription"');
        }
      }
    } catch (e) {
      debugPrint('[VOICE WHISPER] Backend upload notice: $e');
    } finally {
      _deleteQuietly(file);
    }
  }

  // --------------------------------------------------------------------------
  // WAKE PHRASE MATCHING & TRIGGER
  // --------------------------------------------------------------------------
  void _fireTrigger(String source) {
    final now = DateTime.now();
    final last = _lastTriggerAt;
    if (last != null && now.difference(last) < _triggerCooldown) return;
    _lastTriggerAt = now;
    debugPrint('🚨 [VOICE CONFIRMED] Emergency phrase detected via $source! Triggering SOS alarm.');
    onWakeWordDetected?.call();
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  bool _matchesWakePhrase(String heard) {
    if (heard.isEmpty) return false;
    final cleanHeard = heard
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanHeard.isEmpty) return false;

    // 1. Check custom configured phrase
    if (_matchesSinglePhrase(cleanHeard, _wakePhrase)) return true;

    // 2. Check all default emergency phrases (Kiswahili & English)
    for (final phrase in defaultWakePhrases) {
      if (_matchesSinglePhrase(cleanHeard, phrase)) return true;
    }

    return false;
  }

  // Phonetic aliases & sound-alikes for Kiswahili & English emergency triggers
  // Crucial when Google STT on Android is in English mode but user speaks Kiswahili
  static const Map<String, List<String>> _phoneticAliases = {
    'tuma': ['tuma', 'to my', 'two my', 'to ma', 'tumor', 'touma', 'thuma', '2 my', 'to me', 'thomas', 'tumaa'],
    'msaada': ['msaada', 'masada', 'msada', 'sada', 'musaada', 'mussada', 'musada', 'masaha', 'massada', 'mother', 'my sada', 'asada', 'saad', 'sahada'],
    'nisaidie': ['nisaidie', 'saidie', 'knee side', 'ni saidie', 'saidia', 'nisadie', 'side ya', 'inside', 'knee side yeah', 'said here', 'knee said'],
    'piga': ['piga', 'peter', 'picker', 'bigger', 'peega', 'pika', 'beater', 'pig'],
    'polisi': ['polisi', 'police', 'policeman', 'polici', 'polize', 'please', 'polisi'],
    'okoa': ['okoa', 'okwa', 'okowa', 'oak', 'aqua', 'accord'],
    'maisha': ['maisha', 'my share', 'maysha', 'may sha', 'mysha', 'misha'],
    'help': ['help', 'help me', 'hell', 'held'],
    'emergency': ['emergency', 'emergent'],
    'save': ['save', 'safe'],
  };

  bool _matchesSinglePhrase(String heard, String target) {
    final cleanHeard = heard
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cleanTarget = target
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanTarget.isEmpty || cleanHeard.isEmpty) return false;

    // 1. Direct substring match
    if (cleanHeard.contains(cleanTarget)) return true;

    // 2. Target keywords analysis with phonetic aliases
    final targetWords = cleanTarget.split(' ').where((w) => w.isNotEmpty).toList();
    if (targetWords.isEmpty) return false;

    int matchedKeywords = 0;
    for (final word in targetWords) {
      if (cleanHeard.contains(word)) {
        matchedKeywords++;
        continue;
      }
      // Check phonetic sound-alikes (crucial for Kiswahili spoken on English STT engine)
      final aliases = _phoneticAliases[word];
      if (aliases != null) {
        bool aliasFound = false;
        for (final alias in aliases) {
          if (cleanHeard.contains(alias)) {
            aliasFound = true;
            break;
          }
        }
        if (aliasFound) {
          matchedKeywords++;
          continue;
        }
      }
    }

    // If all words in the target phrase matched
    if (matchedKeywords >= targetWords.length) return true;

    // For 2-word phrases like "tuma msaada", matching "msaada" or "tuma" plus emergency context is valid
    if (targetWords.length >= 2 && matchedKeywords >= 1) {
      if (cleanHeard.contains('msaada') ||
          cleanHeard.contains('masada') ||
          cleanHeard.contains('sada') ||
          cleanHeard.contains('help') ||
          cleanHeard.contains('saidie') ||
          cleanHeard.contains('police') ||
          cleanHeard.contains('polisi')) {
        return true;
      }
    }

    return false;
  }

  /// Interactive Voice Testing (Works with on-device speech recognizer and phonetic dictionary)
  Future<Map<String, dynamic>> recordAndTestPhrase(
    String candidatePhrase, {
    Duration duration = const Duration(seconds: 6),
    Function(String partialText)? onPartialHeard,
  }) async {
    try {
      if (!await _ensureMicPermission()) {
        return {'success': false, 'error': 'Microphone permission denied'};
      }

      // Stop continuous listener temporarily
      stopListening();
      await Future.delayed(const Duration(milliseconds: 300));

      // Attempt 1: Try on-device recognition for rapid real-time verification
      final testSpeech = stt.SpeechToText();
      final initOk = await testSpeech.initialize();
      if (initOk) {
        final completer = Completer<Map<String, dynamic>>();
        String capturedWords = '';

        // Detect if Kiswahili locale (sw_KE) is supported on device
        String? swLocale;
        try {
          final locales = await testSpeech.locales();
          for (final loc in locales) {
            if (loc.localeId.toLowerCase().startsWith('sw')) {
              swLocale = loc.localeId;
              break;
            }
          }
        } catch (_) {}

        await testSpeech.listen(
          localeId: swLocale,
          onResult: (result) {
            capturedWords = result.recognizedWords;
            onPartialHeard?.call(capturedWords);
            final isMatched = _matchesSinglePhrase(capturedWords, candidatePhrase) ||
                _matchesWakePhrase(capturedWords);
            if (isMatched && !completer.isCompleted) {
              completer.complete({
                'success': true,
                'transcription': capturedWords,
                'matched': true,
                'keyword': candidatePhrase,
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: true,
            cancelOnError: false,
            listenFor: duration,
            pauseFor: const Duration(seconds: 3),
          ),
        );

        // Wait for result or duration timeout
        Timer(duration + const Duration(milliseconds: 800), () {
          if (!completer.isCompleted) {
            final isMatched = _matchesSinglePhrase(capturedWords, candidatePhrase) ||
                _matchesWakePhrase(capturedWords);
            completer.complete({
              'success': true,
              'transcription': capturedWords.isNotEmpty ? capturedWords : 'No words detected',
              'matched': isMatched,
              'keyword': candidatePhrase,
            });
          }
        });

        final result = await completer.future;
        try { testSpeech.stop(); } catch (_) {}
        // Resume continuous listening
        if (_isEnabled) unawaited(startListening());
        return result;
      }

      // Attempt 2: AudioRecorder + Whisper backend fallback
      final testRecorder = AudioRecorder();
      final testPath = '${Directory.systemTemp.path}/voice_test_${DateTime.now().millisecondsSinceEpoch}.wav';

      await testRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: testPath,
      );

      await Future.delayed(duration);
      final recordedPath = await testRecorder.stop();
      await testRecorder.dispose();

      final file = File(recordedPath ?? testPath);
      if (!file.existsSync() || file.lengthSync() < 500) {
        if (_isEnabled) unawaited(startListening());
        return {'success': false, 'error': 'No audio recorded. Please speak clearly into microphone.'};
      }

      final baseUrl = await AppConstants.getEffectiveBackendUrl();
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/voice/detect'))
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..fields['auto_trigger'] = 'false'
        ..fields['custom_phrase'] = candidatePhrase
        ..files.add(await http.MultipartFile.fromPath('audio', file.path, filename: 'test.wav'));

      final streamed = await request.send().timeout(const Duration(seconds: 15));
      final res = await http.Response.fromStream(streamed);
      try { file.deleteSync(); } catch (_) {}

      if (_isEnabled) unawaited(startListening());

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final transcription = (data['transcription'] ?? '').toString();
        final matched = data['emergency_detected'] == true ||
            _matchesSinglePhrase(transcription, candidatePhrase);
        return {
          'success': true,
          'transcription': transcription,
          'matched': matched,
          'keyword': data['matched_keyword'] ?? candidatePhrase,
        };
      } else {
        return {'success': false, 'error': 'Backend returned status ${res.statusCode}'};
      }
    } catch (e) {
      debugPrint('[VOICE TEST ERROR] $e');
      if (_isEnabled) unawaited(startListening());
      return {'success': false, 'error': e.toString()};
    }
  }
}
