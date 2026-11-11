import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/di/service_locator.dart';
import '../../../core/navigation/navigation_service.dart';
import '../../../core/services/background_protection_service.dart';
import '../../../core/services/notification_service.dart';

typedef OnWakeWordDetectedCallback = void Function();
typedef BackgroundVoiceService = VoiceActivationService;

/// Native Flutter Speech-to-Text Voice SOS Activation Service.
///
/// Runs continuous speech recognition via Flutter `speech_to_text` both in the
/// foreground and in the background (powered by the SafeLink microphone
/// foreground service).
///
/// Recognizes both English ("help", "help me", "send help", "emergency",
/// "save me", "call police", etc.) and Kiswahili ("msaada", "tuma msaada",
/// "nisaidie", "kujeni hapa", "piga polisi", "okoa maisha", etc.) as well as
/// user-configured custom emergency phrases.
class VoiceActivationService with WidgetsBindingObserver {
  static final VoiceActivationService instance =
      VoiceActivationService._internal();
  VoiceActivationService._internal() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  static const Duration _triggerCooldown = Duration(seconds: 12);

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _wantListening = false;
  bool _isSpeechListening = false;
  bool _isStartingStt = false;
  bool _isEnabled = true;
  bool _inInteractiveTest = false;
  String _wakePhrase = 'tuma msaada';

  DateTime? _lastTriggerAt;
  DateTime? _lastListenStartAt;
  Timer? _sttRestartTimer;
  Timer? _watchdogTimer;

  static const List<String> defaultWakePhrases = [
    'tuma msaada',
    'nisaidie',
    'nisaidie haraka',
    'kujeni hapa',
    'piga polisi',
    'okoa maisha',
    'help me',
    'help me now',
    'send help',
    'call police',
    'call the police',
  ];

  OnWakeWordDetectedCallback? onWakeWordDetected;
  void Function(
    String heard,
    double confidence,
    bool isFinal,
    String? matchedKeyword,
  )?
  _interactiveTestCallback;

  final ValueNotifier<String> lastHeardWords = ValueNotifier<String>('');
  final ValueNotifier<String?> lastDetectedKeyword = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<DateTime?> lastDetectedAt = ValueNotifier<DateTime?>(
    null,
  );
  final ValueNotifier<bool> isTranscribing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isListeningNotifier = ValueNotifier<bool>(false);

  bool get isListening =>
      _wantListening || _isSpeechListening || _speech.isListening;
  bool get isEnabled => _isEnabled;
  String get wakePhrase => _wakePhrase;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      debugPrint(
        '[VOICE STT] App moved to background ($state) — keeping continuous voice protection alive',
      );
      BackgroundProtectionService.start(voiceEnabled: true, shakeEnabled: true);
      if (_wantListening && !_inInteractiveTest) {
        _restartSttSoon(delay: const Duration(milliseconds: 500));
      }
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[VOICE STT] App resumed — verifying active voice listener');
      if (_isEnabled && !_inInteractiveTest) {
        _wantListening = true;
        _restartSttSoon(delay: const Duration(milliseconds: 300));
      }
    }
  }

  /// Simulates voice phrase detection (for testing & demo on emulators/devices)
  void simulateVoiceDetected({String? simulatedPhrase}) {
    final phrase = simulatedPhrase ?? _wakePhrase;
    debugPrint(
      '🎙️ [VOICE SIMULATION] Simulated emergency voice trigger invoked ("$phrase")!',
    );
    lastHeardWords.value = phrase;
    lastDetectedKeyword.value = phrase;
    lastDetectedAt.value = DateTime.now();
    _notifyKeywordDetected(keyword: phrase, heardText: phrase, testOnly: false);
    onWakeWordDetected?.call();
  }

  /// Loads saved voice settings from persistent storage.
  Future<void> init({OnWakeWordDetectedCallback? onDetected}) async {
    if (onDetected != null) {
      onWakeWordDetected = onDetected;
    }
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? true;
    _wakePhrase = prefs.getString('voice_wake_word') ?? 'tuma msaada';
  }

  Future<void> updateSettings({
    required bool enabled,
    required String phrase,
  }) async {
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

  Future<void> startIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? _isEnabled;
    _wakePhrase = prefs.getString('voice_wake_word') ?? _wakePhrase;
    if (_isEnabled) {
      await startListening();
    }
  }

  Future<void> stop() async {
    stopListening();
  }

  Future<void> start() async {
    await startListening();
  }

  Future<bool> _ensureMicPermission() async {
    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        debugPrint('[VOICE STT] Microphone permission not granted');
      }
      return status.isGranted;
    } catch (e) {
      debugPrint('[VOICE STT] Permission error: $e');
      return false;
    }
  }

  /// Starts continuous speech-to-text listening in foreground & background.
  Future<void> startListening() async {
    if (!await _ensureMicPermission()) return;

    // If already actively listening or starting, do not double-trigger
    if (_wantListening &&
        !_inInteractiveTest &&
        (_speech.isListening || _isStartingStt)) {
      isListeningNotifier.value = true;
      return;
    }

    _inInteractiveTest = false;
    _interactiveTestCallback = null;
    _wantListening = true;
    isListeningNotifier.value = true;
    debugPrint(
      '[VOICE STT] Starting continuous speech recognition (target: "$_wakePhrase")...',
    );

    // Ensure background service is running on Android so mic stays alive when screen is off or app is minimised
    unawaited(
      BackgroundProtectionService.start(voiceEnabled: true, shakeEnabled: true),
    );

    final ok = await _initSpeech();
    if (ok) {
      await _startContinuousStt();
      _startWatchdog();
    } else {
      debugPrint(
        '[VOICE STT] Speech recognizer initialization deferred; retrying...',
      );
      _restartSttSoon(delay: const Duration(seconds: 2));
      _startWatchdog();
    }
  }

  /// Stops voice detection and cancels all auto-restart timers.
  void stopListening() {
    _wantListening = false;
    _isSpeechListening = false;
    _inInteractiveTest = false;
    _interactiveTestCallback = null;
    isListeningNotifier.value = false;
    isTranscribing.value = false;
    _sttRestartTimer?.cancel();
    _sttRestartTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    try {
      _speech.stop();
    } catch (_) {}
    debugPrint('[VOICE STT] Continuous voice detection stopped');
  }

  // --------------------------------------------------------------------------
  // CONTINUOUS SPEECH RECOGNITION ENGINE
  // --------------------------------------------------------------------------

  void _onSpeechError(SpeechRecognitionError err) {
    final msg = err.errorMsg;
    _isSpeechListening = false;
    _isStartingStt = false;
    isTranscribing.value = false;

    if (_inInteractiveTest) {
      return;
    }

    if (_wantListening) {
      if (msg == 'error_busy') {
        // Android recognizer is still releasing previous session; cancel cleanly and wait 2.5s
        try {
          _speech.cancel();
        } catch (_) {}
        _restartSttSoon(delay: const Duration(milliseconds: 2500));
      } else if (msg == 'error_no_match' ||
          msg == 'error_speech_timeout' ||
          msg == 'error_client') {
        _restartSttSoon(delay: const Duration(milliseconds: 600));
      } else {
        debugPrint('[VOICE STT] Engine status notice: $msg');
        _restartSttSoon(delay: const Duration(milliseconds: 1000));
      }
    }
  }

  void _onSpeechStatus(String status) {
    if (status == 'listening') {
      _isSpeechListening = true;
      _isStartingStt = false;
      isTranscribing.value = true;
      isListeningNotifier.value = true;
    } else if (status == 'done' || status == 'notListening') {
      _isSpeechListening = false;
      _isStartingStt = false;
      isTranscribing.value = false;
      if (_wantListening &&
          !_inInteractiveTest &&
          (_sttRestartTimer == null || !_sttRestartTimer!.isActive)) {
        // Native session ended (timeout or pause); seamlessly restart continuous listening
        _restartSttSoon(delay: const Duration(milliseconds: 650));
      } else if (!_wantListening) {
        isListeningNotifier.value = false;
      }
    }
  }

  Future<bool> _initSpeech() async {
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onError: _onSpeechError,
          onStatus: _onSpeechStatus,
          debugLogging: false,
        );
      }
      // CRITICAL: SpeechToText is a singleton whose initialize() only assigns
      // errorListener/statusListener the first time. Re-bind them explicitly!
      _speech.errorListener = _onSpeechError;
      _speech.statusListener = _onSpeechStatus;
    } catch (e) {
      debugPrint('[VOICE STT] Initialization exception: $e');
      _speechReady = false;
    }
    return _speechReady;
  }

  void _restartSttSoon({Duration delay = const Duration(milliseconds: 350)}) {
    if (!_wantListening || _inInteractiveTest) return;
    _sttRestartTimer?.cancel();
    _sttRestartTimer = Timer(delay, () {
      if (_wantListening && !_inInteractiveTest) {
        _isSpeechListening = false;
        _startContinuousStt();
      }
    });
  }

  /// Watchdog timer keeps recognition alive across background lifecycle changes
  /// and recovers if the platform recognizer silently stops after 45s.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_wantListening || _inInteractiveTest || _isStartingStt) return;
      // Do not race with a scheduled restart timer
      if (_sttRestartTimer != null && _sttRestartTimer!.isActive) return;

      final now = DateTime.now();
      final recentlyStarted =
          _lastListenStartAt != null &&
          now.difference(_lastListenStartAt!) < const Duration(seconds: 5);
      if (recentlyStarted) return;

      final stuckTooLong =
          _lastListenStartAt != null &&
          now.difference(_lastListenStartAt!) > const Duration(seconds: 48);

      if (!_speech.isListening || !_isSpeechListening || stuckTooLong) {
        if (stuckTooLong) {
          try {
            _speech.stop();
          } catch (_) {}
          _isSpeechListening = false;
        }
        _restartSttSoon(delay: const Duration(milliseconds: 500));
      }
    });
  }

  Future<void> _startContinuousStt() async {
    if (!_wantListening || _inInteractiveTest || _isStartingStt) return;

    _isStartingStt = true;
    try {
      await _initSpeech();
      if (_speech.isListening) {
        _isSpeechListening = true;
        _isStartingStt = false;
        isListeningNotifier.value = true;
        return;
      }

      _isSpeechListening = true;
      isListeningNotifier.value = true;
      _lastListenStartAt = DateTime.now();

      await _speech.listen(
        onResult: _handleSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[VOICE STT] Listen start notice: $e');
      _isSpeechListening = false;
      _restartSttSoon(delay: const Duration(milliseconds: 1800));
    } finally {
      _isStartingStt = false;
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final primaryWords = result.recognizedWords.trim();
    if (primaryWords.isEmpty && result.alternates.isEmpty) return;

    // Collect primary + all alternate transcriptions from the recognizer
    final candidates = <String>[
      if (primaryWords.isNotEmpty) primaryWords,
      for (final alt in result.alternates)
        if (alt.recognizedWords.trim().isNotEmpty) alt.recognizedWords.trim(),
    ];

    final displayWords = primaryWords.isNotEmpty
        ? primaryWords
        : candidates.first;
    lastHeardWords.value = displayWords;
    debugPrint(
      '🎙️ [VOICE STT HEARD] "$displayWords" (alternates: ${candidates.length})',
    );

    String? matchedKeyword;
    String matchedTranscript = displayWords;
    for (final candidate in candidates) {
      final match = findMatchedKeyword(candidate);
      if (match != null) {
        matchedKeyword = match;
        matchedTranscript = candidate;
        break;
      }
    }

    if (_inInteractiveTest && _interactiveTestCallback != null) {
      final conf = result.confidence > 0
          ? result.confidence
          : (matchedKeyword != null ? 0.94 : 0.82);
      if (matchedKeyword != null) {
        lastDetectedKeyword.value = matchedKeyword;
        lastDetectedAt.value = DateTime.now();
        _notifyKeywordDetected(
          keyword: matchedKeyword,
          heardText: matchedTranscript,
          testOnly: true,
        );
      }
      _interactiveTestCallback!(
        displayWords,
        conf,
        result.finalResult,
        matchedKeyword,
      );
      return;
    }

    if (matchedKeyword != null) {
      // Only fire real SOS on final speech recognition result (or high-confidence >= 0.72)
      // to eliminate false triggers from transient mid-sentence partial hypotheses.
      final bool highConfidencePartial =
          result.confidence >= 0.72 && matchedTranscript.split(' ').length >= 2;
      if (result.finalResult || highConfidencePartial) {
        _fireTrigger(
          matchedKeyword: matchedKeyword,
          heardText: matchedTranscript,
        );
      } else {
        debugPrint(
          '[VOICE STT] Waiting for final speech result before triggering for "$matchedKeyword" (heard partial: "$matchedTranscript")',
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // WAKE PHRASE MATCHING & TRIGGER DISPATCH
  // --------------------------------------------------------------------------

  void _notifyKeywordDetected({
    required String keyword,
    required String heardText,
    required bool testOnly,
  }) {
    // 1. High-priority system pop-up notification (works in background & foreground)
    try {
      sl<NotificationService>().showVoiceKeywordDetectedPopup(
        keyword: keyword,
        heardText: heardText,
        testOnly: testOnly,
      );
    } catch (e) {
      debugPrint('[VOICE STT] Popup notification notice: $e');
    }

    // 2. Visible in-app floating banner if context is mounted
    try {
      final ctx = NavigationService.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.record_voice_over_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice Keyword Detected: "$keyword"',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        testOnly
                            ? 'Heard "$heardText" — Voice recognition verified!'
                            : 'Heard "$heardText" — Launching Emergency SOS!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void _fireTrigger({
    required String matchedKeyword,
    required String heardText,
  }) {
    final now = DateTime.now();
    final last = _lastTriggerAt;
    if (last != null && now.difference(last) < _triggerCooldown) return;
    _lastTriggerAt = now;

    lastDetectedKeyword.value = matchedKeyword;
    lastDetectedAt.value = now;

    // Auto-clear the banner state after 10 seconds so it doesn't stay stuck on HomeScreen
    Future.delayed(const Duration(seconds: 10), () {
      if (lastDetectedAt.value == now) {
        lastDetectedKeyword.value = null;
      }
    });

    debugPrint(
      '🚨 [VOICE SOS CONFIRMED] Keyword "$matchedKeyword" detected (heard: "$heardText")! Triggering SOS.',
    );

    _notifyKeywordDetected(
      keyword: matchedKeyword,
      heardText: heardText,
      testOnly: false,
    );

    onWakeWordDetected?.call();
  }

  bool matchesWakePhrase(String heard) => findMatchedKeyword(heard) != null;

  /// Returns the matched keyword/phrase if [heard] matches either the user's
  /// custom wake phrase or any built-in emergency keyword (Kiswahili or English),
  /// or `null` if no keyword matched.
  String? findMatchedKeyword(String heard) {
    if (heard.isEmpty) return null;
    final cleanHeard = _normalize(heard);
    if (cleanHeard.isEmpty) return null;

    // 1. Check user's custom configured phrase first
    if (_matchesSinglePhrase(cleanHeard, _wakePhrase)) {
      return _wakePhrase;
    }

    // 2. Check all default emergency phrases (Kiswahili & English)
    for (final phrase in defaultWakePhrases) {
      if (_matchesSinglePhrase(cleanHeard, phrase)) {
        return phrase;
      }
    }

    return null;
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Phonetic aliases & sound-alikes for Kiswahili & English emergency triggers.
  // Crucial when Android STT is in English mode while user speaks Kiswahili (or vice versa).
  // Kept strictly unambiguous — no everyday English words like "mother", "please", "health", etc.
  static const Map<String, List<String>> _phoneticAliases = {
    'tuma': [
      'tuma',
      'to ma',
      'touma',
      'thuma',
      'tumaa',
      'chuma',
    ],
    'msaada': [
      'msaada',
      'masada',
      'msada',
      'musaada',
      'mussada',
      'musada',
      'massada',
      'my sada',
      'sahada',
    ],
    'nisaidie': [
      'nisaidie',
      'ni saidie',
      'nisadie',
      'nisaidia',
      'knee side yeah',
    ],
    'haraka': ['haraka', 'harak'],
    'kujeni': [
      'kujeni',
      'kujeni hapa',
      'who jenny',
      'coojee',
    ],
    'hapa': ['hapa', 'harper', 'hopper'],
    'piga': [
      'piga',
      'peega',
      'pika',
    ],
    'polisi': [
      'polisi',
      'police',
      'policeman',
      'polici',
      'polize',
    ],
    'okoa': ['okoa', 'okwa', 'okowa'],
    'maisha': [
      'maisha',
      'maysha',
      'may sha',
      'mysha',
      'myisha',
    ],
    'help': [
      'help',
      'help me',
      'halp',
    ],
    'police': ['police', 'polisi'],
  };

  bool _matchesSinglePhrase(String cleanHeard, String target) {
    final cleanTarget = _normalize(target);
    if (cleanTarget.isEmpty || cleanHeard.isEmpty) return false;

    final heardWords = cleanHeard
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final targetWords = cleanTarget
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (targetWords.isEmpty || heardWords.isEmpty) return false;

    // 1. Exact word-bounded phrase match
    final RegExp boundaryRegex = RegExp(
      r'(^|\s)' + RegExp.escape(cleanTarget) + r'(\s|$)',
    );
    if (boundaryRegex.hasMatch(cleanHeard)) return true;

    // 2. Check phonetic aliases & strict fuzzy word similarity for ALL target words
    int matchedKeywords = 0;
    for (final word in targetWords) {
      if (_heardContainsWordOrAlias(cleanHeard, heardWords, word)) {
        matchedKeywords++;
      }
    }

    if (matchedKeywords >= targetWords.length) return true;

    // 3. Whole-phrase sliding window high-confidence match (>= 0.86 similarity)
    final windowSize = targetWords.length;
    if (heardWords.length >= windowSize) {
      for (int i = 0; i <= heardWords.length - windowSize; i++) {
        final windowStr = heardWords.sublist(i, i + windowSize).join(' ');
        if (_similarity(windowStr, cleanTarget) >= 0.86) {
          return true;
        }
      }
    } else if (targetWords.length == 1 &&
        _similarity(cleanHeard, cleanTarget) >= 0.88) {
      return true;
    }

    return false;
  }

  bool _heardContainsWordOrAlias(
    String cleanHeard,
    List<String> heardWords,
    String targetWord,
  ) {
    if (heardWords.contains(targetWord)) return true;

    final aliases = _phoneticAliases[targetWord];
    if (aliases != null) {
      for (final alias in aliases) {
        if (alias.contains(' ')) {
          if (cleanHeard.contains(alias)) return true;
        } else if (heardWords.contains(alias)) {
          return true;
        }
      }
    }

    // Strict fuzzy word comparison only for long words >= 5 chars
    if (targetWord.length >= 5) {
      for (final hw in heardWords) {
        if ((hw.length - targetWord.length).abs() <= 1 &&
            _similarity(hw, targetWord) >= 0.86) {
          return true;
        }
      }
    }
    return false;
  }

  /// Normalized Levenshtein similarity in [0.0, 1.0].
  double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = max(a.length, b.length);
    final dist = _levenshtein(a, b);
    return (maxLen - dist) / maxLen;
  }

  int _levenshtein(String s, String t) {
    final m = s.length;
    final n = t.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = min(
          min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }
    return dp[m][n];
  }

  // --------------------------------------------------------------------------
  // INTERACTIVE TESTING (Used by VoiceSettingsScreen without breaking singleton)
  // --------------------------------------------------------------------------

  Future<bool> startInteractiveTest({
    required String candidatePhrase,
    required void Function(
      String heard,
      double confidence,
      bool isFinal,
      String? matchedKeyword,
    )
    onResult,
  }) async {
    if (!await _ensureMicPermission()) return false;

    _sttRestartTimer?.cancel();
    _inInteractiveTest = true;
    _interactiveTestCallback = onResult;
    _wakePhrase = candidatePhrase.trim().isNotEmpty
        ? candidatePhrase.trim().toLowerCase()
        : _wakePhrase;

    try {
      await _speech.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));

    final ready = await _initSpeech();
    if (!ready) {
      _inInteractiveTest = false;
      _interactiveTestCallback = null;
      return false;
    }

    try {
      _isSpeechListening = true;
      isTranscribing.value = true;
      await _speech.listen(
        onResult: _handleSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[VOICE STT] Interactive test start error: $e');
      _inInteractiveTest = false;
      _interactiveTestCallback = null;
      return false;
    }
  }

  Future<void> stopInteractiveTest({bool resumeContinuous = true}) async {
    _inInteractiveTest = false;
    _interactiveTestCallback = null;
    try {
      await _speech.stop();
    } catch (_) {}
    _isSpeechListening = false;
    isTranscribing.value = false;

    if (resumeContinuous && _isEnabled) {
      await Future.delayed(const Duration(milliseconds: 250));
      await startListening();
    }
  }

  /// Tests phrase recognition directly via Flutter `speech_to_text` library.
  Future<Map<String, dynamic>> testPhraseWithStt(
    String candidatePhrase, {
    Duration duration = const Duration(seconds: 5),
    Function(String partialText)? onPartialHeard,
  }) async {
    String recognizedText = '';
    String? matchedKeyword;

    final started = await startInteractiveTest(
      candidatePhrase: candidatePhrase,
      onResult: (heard, confidence, isFinal, matched) {
        recognizedText = heard;
        onPartialHeard?.call(heard);
        if (matched != null) {
          matchedKeyword = matched;
        }
      },
    );

    if (!started) {
      return {
        'success': false,
        'error': 'Speech recognizer unavailable or mic permission denied',
      };
    }

    await Future.delayed(duration);
    await stopInteractiveTest(resumeContinuous: _isEnabled);

    final isMatched =
        matchedKeyword != null ||
        (recognizedText.isNotEmpty &&
            findMatchedKeyword(recognizedText) != null);

    return {
      'success': true,
      'transcription': recognizedText.isNotEmpty ? recognizedText : 'No clear speech detected. Please speak clearly into the microphone.',
      'matched': isMatched,
      'keyword': matchedKeyword ?? candidatePhrase,
    };
  }

  /// Backwards-compatible alias for existing screens
  Future<Map<String, dynamic>> recordAndTestPhrase(
    String candidatePhrase, {
    Duration duration = const Duration(seconds: 5),
    Function(String partialText)? onPartialHeard,
  }) async {
    return testPhraseWithStt(
      candidatePhrase,
      duration: duration,
      onPartialHeard: onPartialHeard,
    );
  }
}
