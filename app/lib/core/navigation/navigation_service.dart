import 'package:flutter/material.dart';

/// Centralized navigation service to allow controllers and background services
/// to push routes or show dialogs without needing a BuildContext.
class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get currentContext => navigatorKey.currentContext;

  static Future<T?>? pushNamed<T extends Object?>(String routeName, {Object? arguments}) {
    return navigatorKey.currentState?.pushNamed<T>(routeName, arguments: arguments);
  }

  static void pop<T extends Object?>([T? result]) {
    return navigatorKey.currentState?.pop<T>(result);
  }
}
