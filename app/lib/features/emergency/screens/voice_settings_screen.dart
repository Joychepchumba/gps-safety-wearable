import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme_controller.dart';
import '../../emergency/controllers/emergency_controller.dart';
import '../../emergency/services/voice_activation_service.dart';

/// Callback type so MapPage (or any parent) can react when the wake word fires.
typedef OnWakeWordDetected = void Function();

/// Main Voice Activation configuration page.
/// Aliased as VoiceSettingsScreen for backwards compatibility with existing routes.
class VoiceActivationPage extends StatefulWidget {
  final OnWakeWordDetected? onWakeWordDetected;

  const VoiceActivationPage({super.key, this.onWakeWordDetected});

  @override
  State<VoiceActivationPage> createState() => _VoiceActivationPageState();
}

class VoiceSettingsScreen extends StatelessWidget {
  final OnWakeWordDetected? onWakeWordDetected;
  const VoiceSettingsScreen({super.key, this.onWakeWordDetected});

  @override
  Widget build(BuildContext context) {
    return VoiceActivationPage(onWakeWordDetected: onWakeWordDetected);
  }
}

class _VoiceActivationPageState extends State<VoiceActivationPage>
    with SingleTickerProviderStateMixin {
  bool _isEnabled = true;
  String _wakeWord = 'tuma msaada';
  final _wakeWordCtrl = TextEditingController();

  bool _isListening = false;
  bool _triggerSosOnTestMatch = false;
  String _heardText = '';
  String? _matchedKeyword;
  double _confidence = 0.0;
  Timer? _testTimeoutTimer;

  _Status _status = _Status.idle;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _blue = Color(0xFF4FABCB);

  final List<Map<String, String>> _suggestedPhrases = [
    {'phrase': 'tuma msaada', 'label': 'tuma msaada (Swahili)'},
    {'phrase': 'nisaidie', 'label': 'nisaidie (Swahili)'},
    {'phrase': 'kujeni hapa', 'label': 'kujeni hapa (Swahili)'},
    {'phrase': 'nisaidie haraka', 'label': 'nisaidie haraka (Swahili)'},
    {'phrase': 'okoa maisha', 'label': 'okoa maisha (Swahili)'},
    {'phrase': 'piga polisi', 'label': 'piga polisi (Swahili)'},
    {'phrase': 'help me', 'label': 'help me (English)'},
    {'phrase': 'send help', 'label': 'send help (English)'},
    {'phrase': 'call the police', 'label': 'call the police (English)'},
    {'phrase': 'emergency', 'label': 'emergency (English)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.25,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _testTimeoutTimer?.cancel();
    _pulseCtrl.dispose();
    _wakeWordCtrl.dispose();

    // Ensure continuous background voice protection is resumed when leaving
    VoiceActivationService.instance.stopInteractiveTest(resumeContinuous: _isEnabled);
    if (_isEnabled) {
      if (widget.onWakeWordDetected != null) {
        VoiceActivationService.instance.onWakeWordDetected = widget.onWakeWordDetected;
      }
      VoiceActivationService.instance.startIfEnabled();
    } else {
      VoiceActivationService.instance.stop();
    }

    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isEnabled = prefs.getBool('voice_activation_enabled') ?? true;
      _wakeWord = prefs.getString('voice_wake_word') ?? 'tuma msaada';
      _wakeWordCtrl.text = _wakeWord;
    });
  }

  Future<void> _saveSettings() async {
    final trimmed = _wakeWordCtrl.text.trim().toLowerCase();
    if (trimmed.isEmpty) {
      _showSnack('Wake phrase cannot be empty', isError: true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', _isEnabled);
    await prefs.setString('voice_wake_word', trimmed);
    setState(() => _wakeWord = trimmed);

    if (!mounted) return;
    try {
      final emergencyController = context.read<EmergencyController>();
      await emergencyController.updateVoiceSettings(
        enabled: _isEnabled,
        phrase: trimmed,
      );
    } catch (_) {
      await VoiceActivationService.instance.updateSettings(
        enabled: _isEnabled,
        phrase: trimmed,
      );
    }

    _showSnack('Voice settings saved & active in background ✓');
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      _testTimeoutTimer?.cancel();
      await VoiceActivationService.instance.stopInteractiveTest(resumeContinuous: _isEnabled);
      if (mounted) {
        setState(() {
          _isListening = false;
          if (_status == _Status.listening) {
            _status = _heardText.isNotEmpty ? _Status.missed : _Status.idle;
          }
        });
      }
      _pulseCtrl.stop();
      _pulseCtrl.reset();
      return;
    }

    setState(() {
      _isListening = true;
      _heardText = '';
      _matchedKeyword = null;
      _confidence = 0.0;
      _status = _Status.listening;
    });

    _pulseCtrl.repeat(reverse: true);

    final started = await VoiceActivationService.instance.startInteractiveTest(
      candidatePhrase: _wakeWord,
      onResult: (heard, confidence, isFinal, matchedKeyword) {
        if (!mounted) return;
        setState(() {
          _heardText = heard;
          _confidence = confidence;
        });

        if (matchedKeyword != null) {
          _testTimeoutTimer?.cancel();
          setState(() {
            _matchedKeyword = matchedKeyword;
            _isListening = false;
            _status = _Status.detected;
          });
          _pulseCtrl.stop();
          _pulseCtrl.reset();
          VoiceActivationService.instance.stopInteractiveTest(resumeContinuous: _isEnabled);

          if (_triggerSosOnTestMatch) {
            try {
              context.read<EmergencyController>().trigger(TriggerMethod.voiceKeyword);
            } catch (_) {}
          }
        } else if (isFinal) {
          _testTimeoutTimer?.cancel();
          setState(() {
            _isListening = false;
            _status = _Status.missed;
          });
          _pulseCtrl.stop();
          _pulseCtrl.reset();
          VoiceActivationService.instance.stopInteractiveTest(resumeContinuous: _isEnabled);
        }
      },
    );

    if (!started) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _status = _Status.error;
        });
      }
      _pulseCtrl.stop();
      _pulseCtrl.reset();
      _showSnack('Microphone or speech engine unavailable. Check permissions.', isError: true);
      return;
    }

    _testTimeoutTimer?.cancel();
    _testTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_isListening) return;
      VoiceActivationService.instance.stopInteractiveTest(resumeContinuous: _isEnabled);
      setState(() {
        _isListening = false;
        if (_status == _Status.listening) {
          _status = _heardText.isNotEmpty ? _Status.missed : _Status.idle;
        }
      });
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color get _statusColor {
    switch (_status) {
      case _Status.listening:
        return _blue;
      case _Status.detected:
        return Colors.green.shade500;
      case _Status.missed:
        return Colors.orange.shade700;
      case _Status.error:
        return Colors.red.shade600;
      case _Status.idle:
        return Colors.grey.shade500;
    }
  }

  String get _statusText {
    switch (_status) {
      case _Status.listening:
        return _heardText.isEmpty
            ? "Listening… say '$_wakeWord' or 'help me'"
            : 'Hearing live: "$_heardText"';
      case _Status.detected:
        return '✅ DETECTED KEYWORD: "${_matchedKeyword ?? _wakeWord}"\nHeard: "$_heardText" — Pop-up notification sent!';
      case _Status.missed:
        return '❌ Heard: "$_heardText" — did not match "$_wakeWord". Try speaking clearly.';
      case _Status.error:
        return 'Microphone unavailable. Please check permissions and try again.';
      case _Status.idle:
        return 'Tap the microphone to test live keyword recognition.';
    }
  }

  IconData get _micIcon =>
      _isListening ? Icons.mic_rounded : Icons.mic_none_rounded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = context.cardBg;
    final textColor = context.textPrimary;
    final subtextColor = context.textSecondary;
    final borderColor = context.cardBorder;
    final voiceService = VoiceActivationService.instance;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Voice Activation & Background SOS',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Live Background Status Banner ───────────────────────────────
            ValueListenableBuilder<bool>(
              valueListenable: voiceService.isListeningNotifier,
              builder: (context, active, _) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: (active || _isEnabled)
                        ? const Color(0xFF10B981).withValues(alpha: 0.14)
                        : Colors.orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (active || _isEnabled)
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (active || _isEnabled) ? Icons.graphic_eq_rounded : Icons.mic_off_rounded,
                        color: (active || _isEnabled) ? const Color(0xFF10B981) : Colors.orange,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (active || _isEnabled)
                                  ? 'BACKGROUND VOICE GUARD ACTIVE'
                                  : 'VOICE GUARD PAUSED',
                              style: TextStyle(
                                color: (active || _isEnabled)
                                    ? const Color(0xFF10B981)
                                    : Colors.orange,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            ValueListenableBuilder<String>(
                              valueListenable: voiceService.lastHeardWords,
                              builder: (context, lastHeard, _) {
                                return Text(
                                  lastHeard.isNotEmpty
                                      ? 'Last heard: "$lastHeard"'
                                      : 'Listening for "$_wakeWord", "help me", "nisaidie", "piga polisi"…',
                                  style: TextStyle(color: textColor, fontSize: 12),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── Recent Detected Keyword Banner ──────────────────────────────
            ValueListenableBuilder<String?>(
              valueListenable: voiceService.lastDetectedKeyword,
              builder: (context, detectedKw, _) {
                if (detectedKw == null || detectedKw.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF059669).withValues(alpha: 0.22),
                        const Color(0xFF10B981).withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF10B981), width: 1.4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'KEYWORD DETECTED & NOTIFIED',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Matched phrase: "$detectedKw"',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          voiceService.lastDetectedKeyword.value = null;
                        },
                        child: const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── Enable toggle card ──────────────────────────────────────────
            _card(
              cardColor: cardColor,
              borderColor: borderColor,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Voice Activation (Foreground & Background)',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Continuously listens for your emergency keywords even when the app is minimized or screen is locked, and pops up an instant notification when detected.',
                    style: TextStyle(color: subtextColor, fontSize: 12.5),
                  ),
                ),
                value: _isEnabled,
                activeTrackColor: _blue,
                activeThumbColor: Colors.white,
                onChanged: (v) {
                  setState(() => _isEnabled = v);
                  _saveSettings();
                },
              ),
            ),

            const SizedBox(height: 20),

            // ── Wake word config card ───────────────────────────────────────
            _sectionLabel('WAKE WORD & SUPPORTED KEYWORDS', subtextColor),
            _card(
              cardColor: cardColor,
              borderColor: borderColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a preset phrase below or type your own custom phrase. Built-in emergency phrases ("tuma msaada", "nisaidie", "piga polisi", "help me", "emergency", "call police") are also always recognized.',
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // Kiswahili + English Dual Mode info box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B382B) : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2E7D32) : const Color(0xFF81C784),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🇰🇪 ', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Bilingual Phonetic Engine Active: Recognizes both Kiswahili '
                            '("tuma msaada", "nisaidie", "kujeni hapa", "piga polisi") and English '
                            '("help me", "send help", "emergency") automatically without switching phone language.',
                            style: TextStyle(
                              color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Preset chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedPhrases.map((item) {
                      final isSelected =
                          _wakeWordCtrl.text.trim().toLowerCase() == item['phrase']!.toLowerCase();
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: _blue.withValues(alpha: 0.2),
                        backgroundColor: context.surfaceBg,
                        labelStyle: TextStyle(
                          color: isSelected ? _blue : textColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? _blue : borderColor,
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _wakeWordCtrl.text = item['phrase']!;
                              _wakeWord = item['phrase']!;
                            });
                            _saveSettings();
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _wakeWordCtrl,
                    style: TextStyle(color: textColor, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. tuma msaada, nisaidie, help me',
                      hintStyle: TextStyle(
                        color: subtextColor.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.record_voice_over_rounded,
                        color: _blue,
                      ),
                      filled: true,
                      fillColor: context.inputBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _blue, width: 1.5),
                      ),
                    ),
                    onChanged: (v) => setState(() => _wakeWord = v.trim()),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _saveSettings,
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Save Wake Word',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Test detection card ─────────────────────────────────────────
            _sectionLabel('TEST LIVE VOICE DETECTION', subtextColor),
            _card(
              cardColor: cardColor,
              borderColor: borderColor,
              child: Column(
                children: [
                  Text(
                    'Tap the microphone and speak your wake phrase ("$_wakeWord" or "help me").\nYou will see your words transcribed live and receive an instant notification when matched.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),

                  const SizedBox(height: 12),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Also launch 10s SOS Countdown when test phrase matches',
                      style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    value: _triggerSosOnTestMatch,
                    activeTrackColor: _blue,
                    onChanged: (val) => setState(() => _triggerSosOnTestMatch = val),
                  ),

                  const SizedBox(height: 16),

                  // Mic button with pulse animation
                  GestureDetector(
                    onTap: _toggleListening,
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, _) => Transform.scale(
                        scale: _isListening ? _pulseAnim.value : 1.0,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: _isListening
                                ? Colors.red
                                : (_status == _Status.detected ? Colors.green.shade600 : _blue),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isListening ? Colors.red : _blue).withValues(alpha: 0.35),
                                blurRadius: 18,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(_micIcon, color: Colors.white, size: 40),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Status text
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),

                  if (_confidence > 0 && _status != _Status.listening) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        'Recognition Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(color: subtextColor, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Instant Trigger Simulation (Tests pop-up notification & full flow)
                  OutlinedButton.icon(
                    onPressed: () {
                      VoiceActivationService.instance.simulateVoiceDetected(
                        simulatedPhrase: _wakeWord,
                      );
                      setState(() {
                        _heardText = _wakeWord;
                        _matchedKeyword = _wakeWord;
                        _confidence = 0.99;
                        _status = _Status.detected;
                      });
                    },
                    icon: const Icon(Icons.flash_on_rounded, size: 18, color: _blue),
                    label: const Text(
                      'Simulate Voice Keyword Detection & Pop-Up Alert',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _blue),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _blue.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── How it works card ───────────────────────────────────────────
            _sectionLabel('HOW IT WORKS', subtextColor),
            _card(
              cardColor: cardColor,
              borderColor: borderColor,
              child: Column(
                children: [
                  _howItWorksRow(
                    Icons.mic_rounded,
                    'Continuous foreground service keeps the microphone active both inside the app and in the background.',
                    '1',
                    textColor,
                  ),
                  const SizedBox(height: 14),
                  _howItWorksRow(
                    Icons.notifications_active_rounded,
                    'As soon as a keyword is recognized, SafeLink displays the detected phrase and fires a high-priority pop-up notification.',
                    '2',
                    textColor,
                  ),
                  const SizedBox(height: 14),
                  _howItWorksRow(
                    Icons.send_rounded,
                    'Live 3D GPS tracking, SMS to emergency contacts, and BLE/Cloud Community Responder alerts are dispatched.',
                    '3',
                    textColor,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    required Color cardColor,
    required Color borderColor,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.8),
            letterSpacing: 0.9,
          ),
        ),
      );

  Widget _howItWorksRow(IconData icon, String label, String step, Color textColor) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Icon(icon, color: _blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
        ],
      );
}

enum _Status { idle, listening, detected, missed, error }
