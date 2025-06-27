import 'package:flutter/material.dart';

class NavigationService {
  NavigationService._();
  static final navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;
  static NavigatorState? get navigator => navigatorKey.currentState;
} 