import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/constants/app_colors.dart';
import 'core/config/supabase_config.dart';
import 'core/di/service_locator.dart';

import 'features/auth/controllers/auth_controller.dart';
import 'features/home/controllers/home_controller.dart';
import 'features/emergency/controllers/emergency_controller.dart';
import 'features/contacts/controllers/contacts_controller.dart';
import 'features/map/controllers/map_controller.dart';
import 'features/wearable/controllers/wearable_controller.dart';
import 'features/alerts/controllers/alert_controller.dart';

import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/mfa_verify_screen.dart';
import 'features/auth/screens/mfa_setup_screen.dart';
import 'features/auth/screens/reset_password_screen.dart';
import 'features/auth/screens/verify_otp_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/emergency/screens/emergency_screen.dart';
import 'features/contacts/screens/contacts_screen.dart';
import 'features/map/screens/map_screen.dart';
import 'features/wearable/screens/wearable_screen.dart';
import 'features/wearable/screens/pendant_shop_screen.dart';
import 'features/alerts/screens/alert_history_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/emergency/screens/voice_activation_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  await setupServiceLocator();

  runApp(const SafeGuardApp());
}

class SafeGuardApp extends StatelessWidget {
  const SafeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => sl<AuthController>()),
        ChangeNotifierProvider(create: (_) => sl<HomeController>()),
        ChangeNotifierProvider(create: (_) => sl<EmergencyController>()),
        ChangeNotifierProvider(create: (_) => sl<ContactsController>()),
        ChangeNotifierProvider(create: (_) => sl<MapController>()),
        ChangeNotifierProvider(create: (_) => sl<WearableController>()),
        ChangeNotifierProvider(create: (_) => sl<AlertController>()),
      ],
      child: MaterialApp(
        title: 'SafeLink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            secondary: AppColors.secondary,
            surface: AppColors.surface,
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
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/mfa-verify': (context) => const MfaVerifyScreen(),
          '/mfa-setup': (context) => const MfaSetupScreen(),
          '/reset-password': (context) => const ResetPasswordScreen(),
          '/home': (context) => const HomeScreen(),
          '/emergency': (context) => const EmergencyScreen(),
          '/map': (context) => const MapScreen(),
          '/contacts': (context) => const ContactsScreen(),
          '/alerts': (context) => const AlertHistoryScreen(),
          '/wearable': (context) => const WearableScreen(),
          '/shop': (context) => const PendantShopScreen(),
          '/verify-otp': (context) => const VerifyOtpScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/voice-activation': (context) => const VoiceActivationScreen(),
        },

      ),
    );
  }
}
