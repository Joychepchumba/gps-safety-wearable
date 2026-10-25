import 'package:flutter/material.dart';

class AvatarPreset {
  final String id;
  final String name;
  final String emoji;
  final IconData icon;
  final List<Color> gradient;

  const AvatarPreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.icon,
    required this.gradient,
  });
}

class AvatarPresets {
  static const List<AvatarPreset> all = [
    AvatarPreset(
      id: 'guardian',
      name: 'Guardian',
      emoji: '🛡️',
      icon: Icons.shield_rounded,
      gradient: [Color(0xFF0066FF), Color(0xFF00C6FF)],
    ),
    AvatarPreset(
      id: 'cheetah',
      name: 'Cheetah',
      emoji: '🐆',
      icon: Icons.flash_on_rounded,
      gradient: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    ),
    AvatarPreset(
      id: 'falcon',
      name: 'Falcon',
      emoji: '🦅',
      icon: Icons.visibility_rounded,
      gradient: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    ),
    AvatarPreset(
      id: 'lion',
      name: 'Lion',
      emoji: '🦁',
      icon: Icons.favorite_rounded,
      gradient: [Color(0xFFEA580C), Color(0xFFF97316)],
    ),
    AvatarPreset(
      id: 'sentinel',
      name: 'Sentinel',
      emoji: '⚡',
      icon: Icons.security_rounded,
      gradient: [Color(0xFF0D9488), Color(0xFF10B981)],
    ),
    AvatarPreset(
      id: 'lotus',
      name: 'Lotus',
      emoji: '🌸',
      icon: Icons.spa_rounded,
      gradient: [Color(0xFFEC4899), Color(0xFFA855F7)],
    ),
    AvatarPreset(
      id: 'star',
      name: 'Nova Star',
      emoji: '🌟',
      icon: Icons.star_rounded,
      gradient: [Color(0xFFEAB308), Color(0xFFF59E0B)],
    ),
    AvatarPreset(
      id: 'phoenix',
      name: 'Phoenix',
      emoji: '🔥',
      icon: Icons.local_fire_department_rounded,
      gradient: [Color(0xFFDC2626), Color(0xFFF43F5E)],
    ),
  ];

  static AvatarPreset getById(String? id) {
    if (id == null || id.isEmpty) return all.first;
    return all.firstWhere(
      (a) => a.id == id,
      orElse: () => all.first,
    );
  }

  static Widget renderWidget({
    required String? avatarId,
    String? fallbackName,
    double size = 48,
    Border? border,
  }) {
    final preset = getById(avatarId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: preset.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: border ?? Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: preset.gradient.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          preset.emoji,
          style: TextStyle(fontSize: size * 0.48),
        ),
      ),
    );
  }
}
