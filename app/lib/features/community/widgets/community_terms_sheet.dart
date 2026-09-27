import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class CommunityTermsSheet extends StatelessWidget {
  const CommunityTermsSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const CommunityTermsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Community Responder',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Terms & Safety Code of Conduct',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 16),

              // Scrollable terms body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildSection(
                      number: '1',
                      title: 'A Serious Community Commitment',
                      content:
                          'Being a Community Responder is a serious responsibility. You volunteer to be an active safety ally for people within your immediate neighborhood. Anyone can register—whether you own a SafeLink smart pendant or just use the mobile app.',
                    ),
                    const SizedBox(height: 16),

                    _buildSection(
                      number: '2',
                      title: 'How 2 km Distress Alerts Work',
                      content:
                          'When another user within a 2.0 km radius triggers an emergency (via pendant, shake, or voice wake word), your phone will receive a high-priority audible siren and vibration notification, even in silent mode, indicating someone nearby needs assistance.',
                    ),
                    const SizedBox(height: 16),

                    _buildSection(
                      number: '3',
                      title: 'Privacy & Minimal Data Sharing',
                      content:
                          'To protect everyone\'s dignity and safety, the app only shares essential information: the victim\'s first name, distance in meters, and GPS coordinates with a Google Maps navigation link. Your personal location is never broadcasted to other users.',
                    ),
                    const SizedBox(height: 16),

                    _buildSection(
                      number: '4',
                      title: 'Safety First — Rules of Engagement',
                      content:
                          '• ALWAYS call police (999) or local emergency services first before taking action.\n• NEVER put yourself in physical danger or attempt to confront violent or armed assailants.\n• Render non-confrontational aid, offer safe shelter, observe from a safe perimeter, or guide police and first responders to the scene.',
                    ),
                    const SizedBox(height: 16),

                    _buildSection(
                      number: '5',
                      title: 'Voluntary & Manageable Anytime',
                      content:
                          'Participation is 100% voluntary. You can pause or disable Community Responder mode at any time in Profile & Settings if you are traveling, busy, or no longer wish to receive alerts.',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Acceptance Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'I Understand & Agree to Guidelines',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required String number,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
