import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/appearance_settings.dart';
import 'theme/lumina_theme.dart';

/// Widget raíz de Lumina Player.
/// Lee y persiste el tema (oscuro/claro) mediante [AppearanceSettings].
class LuminaApp extends StatelessWidget {
  const LuminaApp({super.key});

  void _toggleTheme(bool isDark) {
    final nextMode = isDark ? ThemeMode.dark : ThemeMode.light;
    unawaited(
      AppearanceSettings.instance.setThemeMode(nextMode).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error guardando tema: $e\n$s');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppearanceSettings.instance.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: buildLuminaTheme(brightness: Brightness.light),
          darkTheme: buildLuminaTheme(brightness: Brightness.dark),
          home: SplashScreen(
            themeMode: themeMode,
            onThemeChanged: _toggleTheme,
          ),
        );
      },
    );
  }
}
