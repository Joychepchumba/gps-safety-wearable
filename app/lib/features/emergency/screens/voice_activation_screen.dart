import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../services/voice_activation_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceActivationScreen extends StatefulWidget {
  const VoiceActivationScreen({super.key});

  @override
  State<VoiceActivationScreen> createState() => _VoiceActivationScreenState();
}

class _VoiceActivationScreenState extends State<VoiceActivationScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _phraseController;
  bool _isEnabled = false;
  bool _isTesting = false;
  String _heardText = '';
  late stt.SpeechToText _testSpeech;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _testSpeech = stt.SpeechToText();
    final service = VoiceActivationService.instance;
    _isEnabled = service.isEnabled;
    _phraseController = TextEditingController(text: service.wakePhrase);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _phraseController.dispose();
    if (_isTesting) _testSpeech.stop();
    super.dispose();
  }

  void _toggleTestMic() async {
    if (_isTesting) {
      await _testSpeech.stop();
      _pulseController.stop();
      setState(() {
        _isTesting = false;
      });
      return;
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required to listen for wake phrase.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    final available = await _testSpeech.initialize(
      onError: (val) {
        debugPrint('[VOICE TEST] Error: $val');
        if (mounted) {
          setState(() {
            _isTesting = false;
            _heardText = 'Microphone notice: ${val.errorMsg}';
          });
          _pulseController.stop();
        }
      },
    );

    if (available) {
      setState(() {
        _isTesting = true;
        _heardText = 'Listening... Speak your phrase clearly.';
      });
      _pulseController.repeat(reverse: true);

      _testSpeech.listen(
        onResult: (result) {
          setState(() {
            _heardText = result.recognizedWords;
          });
          final target = _phraseController.text.trim().toLowerCase();
          final heard = result.recognizedWords.toLowerCase();
          if (heard.contains(target) || _matchesPhrase(heard, target)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Wake phrase recognized successfully!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition is not available or disabled on this device.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _matchesPhrase(String heard, String target) {
    final targets = target.split(' ');
    int matched = 0;
    for (final t in targets) {
      if (t.isNotEmpty && heard.contains(t)) matched++;
    }
    return matched >= targets.length && targets.isNotEmpty;
  }

  Future<void> _saveSettings() async {
    final phrase = _phraseController.text.trim();
    if (phrase.split(' ').length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wake phrase must contain at least 2 words (e.g. "tuma msaada") to prevent false alarms.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    await VoiceActivationService.instance.updateSettings(
      enabled: _isEnabled,
      phrase: phrase,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice activation settings saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Voice Wake Word SOS',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.record_voice_over_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hands-Free Voice Activation',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Speak your secret phrase aloud when unable to touch your phone or pendant to trigger instant SOS.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Enable Switch Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enable Voice Activation',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Listen in background for wake phrase',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isEnabled,
                      activeTrackColor: AppColors.primary,
                      activeThumbColor: Colors.white,
                      onChanged: (val) {
                        setState(() => _isEnabled = val);
                        _saveSettings();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Wake Phrase Input Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Emergency Wake Phrase',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Examples: "tuma msaada", "help me now", "save me please". At least 2 words required.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phraseController,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        hintText: 'e.g. tuma msaada',
                        prefixIcon: const Icon(Icons.mic, color: AppColors.primary, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Mic Testing Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Text(
                      'TEST MICROPHONE RECOGNITION',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.0, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _toggleTestMic,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isTesting ? _pulseAnimation.value : 1.0,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isTesting ? AppColors.sosRed : AppColors.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isTesting ? AppColors.sosRed : AppColors.primary).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isTesting ? Icons.stop_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isTesting ? 'Tap to Stop Test' : 'Tap to Test Phrase',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _isTesting ? AppColors.sosRed : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_heardText.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          _heardText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Save Voice Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
