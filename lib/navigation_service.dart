import 'package:flutter/material.dart';

class NavigationService {
  NavigationService._();
  static final navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;
  static NavigatorState? get navigator => navigatorKey.currentState;

  /// 安全地跳转到页面
  static bool safeNavigateTo(Widget page) {
    try {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => page),
        );
        return true;
      } else {
        print('NavigationService: Context is not available or mounted');
        return false;
      }
    } catch (e) {
      print('NavigationService: Navigation error: $e');
      return false;
    }
  }

  /// 安全地显示SnackBar
  static bool safeShowSnackBar(String message, {Color backgroundColor = Colors.red}) {
    try {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 3),
          ),
        );
        return true;
      } else {
        print('NavigationService: Context is not available for showing snackbar');
        return false;
      }
    } catch (e) {
      print('NavigationService: Error showing snackbar: $e');
      return false;
    }
  }
} 