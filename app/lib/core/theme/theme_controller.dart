import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class ThemeController extends ChangeNotifier {
  static const String _prefKey = 'app_theme_mode';
  ThemeMode _themeMode = ThemeMode.light;
  static bool isDark = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    return false;
  }

  ThemeController() {
    _loadTheme();
  }

  void _syncStatic() {
    isDark = isDarkMode;
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefKey) ?? 'light';
      if (modeStr == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (modeStr == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
      _syncStatic();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _syncStatic();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'light';
      if (mode == ThemeMode.dark) modeStr = 'dark';
      if (mode == ThemeMode.system) modeStr = 'system';
      await prefs.setString(_prefKey, modeStr);
    } catch (_) {}
  }

  Future<void> toggleDarkMode() async {
    if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }

  ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: AppColors.background,
      cardColor: Colors.white,
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0,
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B0F19),
      cardColor: const Color(0xFF151C2C),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF151C2C)),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF151C2C),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0B0F19),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF64748B),
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: Color(0xFF151C2C),
        onSurface: Colors.white,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0F19),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

extension ThemeColorsExt on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get scaffoldBg => isDarkMode ? const Color(0xFF0B0F19) : AppColors.background;
  Color get surfaceBg => isDarkMode ? const Color(0xFF151C2C) : AppColors.surface;
  Color get cardBg => isDarkMode ? const Color(0xFF151C2C) : Colors.white;
  Color get cardBorder => isDarkMode ? const Color(0xFF1E293B) : AppColors.border;
  Color get textPrimary => isDarkMode ? Colors.white : AppColors.textPrimary;
  Color get textSecondary => isDarkMode ? const Color(0xFF94A3B8) : AppColors.textSecondary;
  Color get textMuted => isDarkMode ? const Color(0xFF64748B) : AppColors.textMuted;
  Color get inputBg => isDarkMode ? const Color(0xFF1E293B) : AppColors.inputBg;
}
