import 'package:get_it/get_it.dart';
import '../theme/theme_controller.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../services/ble_service.dart';
import '../services/sms_service.dart';
import '../services/notification_service.dart';
import '../services/shake_detection_service.dart';
import '../../features/emergency/services/voice_activation_service.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/home/controllers/home_controller.dart';
import '../../features/emergency/controllers/emergency_controller.dart';
import '../../features/contacts/controllers/contacts_controller.dart';
import '../../features/map/controllers/map_controller.dart';
import '../../features/wearable/controllers/wearable_controller.dart';
import '../../features/alerts/controllers/alert_controller.dart';

final sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Services (Lazy Singletons)
  if (!sl.isRegistered<SupabaseService>()) {
    sl.registerLazySingleton(() => SupabaseService());
  }
  if (!sl.isRegistered<LocationService>()) {
    sl.registerLazySingleton(() => LocationService());
  }
  if (!sl.isRegistered<ShakeDetectionService>()) {
    sl.registerLazySingleton(() => ShakeDetectionService());
  }
  if (!sl.isRegistered<BleService>()) {
    sl.registerLazySingleton(() => BleService());
  }
  if (!sl.isRegistered<SmsService>()) {
    sl.registerLazySingleton(() => SmsService());
  }
  if (!sl.isRegistered<NotificationService>()) {
    sl.registerLazySingleton(() => NotificationService());
  }
  if (!sl.isRegistered<VoiceActivationService>()) {
    sl.registerLazySingleton(() => VoiceActivationService.instance);
  }

  // Controllers (Singletons for shared emergency state)
  if (!sl.isRegistered<AuthController>()) {
    sl.registerLazySingleton(() => AuthController());
  }
  if (!sl.isRegistered<HomeController>()) {
    sl.registerFactory(() => HomeController());
  }
  if (!sl.isRegistered<EmergencyController>()) {
    sl.registerLazySingleton(() => EmergencyController());
  }
  if (!sl.isRegistered<ContactsController>()) {
    sl.registerFactory(() => ContactsController());
  }
  if (!sl.isRegistered<MapController>()) {
    sl.registerFactory(() => MapController());
  }
  if (!sl.isRegistered<WearableController>()) {
    sl.registerLazySingleton(() => WearableController());
  }
  if (!sl.isRegistered<AlertController>()) {
    sl.registerFactory(() => AlertController());
  }
  if (!sl.isRegistered<ThemeController>()) {
    sl.registerLazySingleton(() => ThemeController());
  }
}
