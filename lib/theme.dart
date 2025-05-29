import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    const seed = Color(0xFF3A4E50); // 莫蘭迪綠
    const bg = Color.fromARGB(255, 255, 250, 243); // 米色背景

    final base = ThemeData(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        background: bg,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(
        bodyColor: seed,
        displayColor: seed,
      ),
    );
  }
}
