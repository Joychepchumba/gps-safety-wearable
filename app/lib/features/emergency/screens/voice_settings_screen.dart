import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../emergency/controllers/emergency_controller.dart';
import '../../emergency/services/voice_activation_service.dart';
import '../../../core/di/service_locator.dart';

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final VoiceActivationService _voiceService = sl<VoiceActivationService>();
  final TextEditingController _customPhraseController = TextEditingController();

  bool _isListeningEnabled = true;
  String _selectedPhrase = 'tuma msaada';
  bool _isTesting = false;
  String? _testResultText;
  bool? _testResultMatched;

  final List<Map<String, String>> _suggestedPhrases = [
    {'phrase': 'tuma msaada', 'label': 'Tuma msaada (Swahili - Send help)'},
    {'phrase': 'nisaidie', 'label': 'Nisaidie (Swahili - Help me)'},
    {'phrase': 'piga polisi', 'label': 'Piga polisi (Swahili - Call police)'},
    {'phrase': 'okoa maisha', 'label': 'Okoa maisha (Swahili - Save life)'},
    {'phrase': 'send help', 'label': 'Send help (English)'},
    {'phrase': 'help me', 'label': 'Help me (English)'},
    {'phrase': 'emergency', 'label': 'Emergency (English)'},
    {'phrase': 'call the police', 'label': 'Call the police (English)'},
  ];

  @override
  void initState() {
    super.initState();
    _isListeningEnabled = _voiceService.isEnabled;
    _selectedPhrase = _voiceService.wakePhrase;
    _customPhraseController.text = _selectedPhrase;
  }

  @override
  void dispose() {
    _customPhraseController.dispose();
    super.dispose();
  }

  Future<void> _testVoiceWithModel() async {
    final phraseToTest = _customPhraseController.text.trim();
    if (phraseToTest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or type a phrase first')),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testResultText = null;
      _testResultMatched = null;
    });

    final res = await _voiceService.recordAndTestPhrase(
      phraseToTest,
      duration: const Duration(seconds: 6),
      onPartialHeard: (partial) {
        if (mounted) {
          setState(() {
            _testResultText = 'Hearing: "$partial"...';
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      if (res['success'] == true) {
        final transcription = res['transcription'] as String;
        final matched = res['matched'] as bool;
        _testResultText = transcription.isNotEmpty
            ? 'Model Heard: "$transcription"'
            : 'Model did not catch clear speech. Speak clearly into mic.';
        _testResultMatched = matched;
      } else {
        _testResultText = res['error'] ?? 'Audio verification failed';
        _testResultMatched = false;
      }
    });
  }

  Future<void> _saveVoiceSettings() async {
    final custom = _customPhraseController.text.trim();
    final chosen = custom.isNotEmpty ? custom : _selectedPhrase;

    final emergencyController = context.read<EmergencyController>();
    await emergencyController.updateVoiceSettings(
      enabled: _isListeningEnabled,
      phrase: chosen,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Voice SOS updated: "$chosen"'),
        backgroundColor: AppColors.success,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Voice SOS Configuration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Multilingual Speech AI',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Powered by on-device and backend multilingual Whisper model (English & Kiswahili).',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Enable Toggle Switch
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: const Text(
                  'Continuous Voice Detection',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                subtitle: const Text(
                  'Listens for your trigger phrase even in background or locked screen',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                value: _isListeningEnabled,
                activeTrackColor: AppColors.primary,
                onChanged: (val) {
                  setState(() => _isListeningEnabled = val);
                },
              ),
            ),
            const SizedBox(height: 20),

            // Select Phrase Section
            const Text(
              'Select or Customize Your Emergency Phrase',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),

            // Preset options
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestedPhrases.map((item) {
                final isSelected = _selectedPhrase.toLowerCase() == item['phrase']!.toLowerCase() &&
                    _customPhraseController.text.toLowerCase() == item['phrase']!.toLowerCase();
                return ChoiceChip(
                  label: Text(item['label']!),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedPhrase = item['phrase']!;
                        _customPhraseController.text = item['phrase']!;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Custom Phrase Input Field
            TextField(
              controller: _customPhraseController,
              decoration: InputDecoration(
                labelText: 'Custom Emergency Phrase',
                hintText: 'e.g. tuma msaada haraka, save me now',
                prefixIcon: const Icon(Icons.record_voice_over_rounded, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => _customPhraseController.clear(),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                setState(() => _selectedPhrase = val);
              },
            ),
            const SizedBox(height: 24),

            // Interactive Voice Testing Section
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hearing_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Test With Your Voice',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Speak your chosen phrase for 4 seconds to test how the AI model recognizes your voice and dialect.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testVoiceWithModel,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.mic_external_on_rounded, color: Colors.white),
                    label: Text(
                      _isTesting ? 'Listening... Speak your phrase now!' : 'Record & Test Recognition',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTesting ? AppColors.sosRed : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Simulation Button for Instant Verification
                  OutlinedButton.icon(
                    onPressed: () {
                      _voiceService.simulateVoiceDetected();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulated Voice SOS alert triggered!'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    },
                    icon: const Icon(Icons.flash_on_rounded, size: 18, color: AppColors.primary),
                    label: const Text(
                      'Test Full Emergency Flow (Simulate Trigger)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  if (_testResultText != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _testResultMatched == true
                            ? AppColors.success.withValues(alpha: 0.12)
                            : AppColors.sosRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _testResultMatched == true ? AppColors.success : AppColors.sosRed,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _testResultMatched == true ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                color: _testResultMatched == true ? AppColors.success : AppColors.sosRed,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _testResultMatched == true
                                    ? 'Recognition Matched & Verified!'
                                    : 'Phrase Not Detected',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _testResultMatched == true ? AppColors.success : AppColors.sosRed,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _testResultText!,
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Save Configuration Button
            ElevatedButton(
              onPressed: _saveVoiceSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Save Voice Activation Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
