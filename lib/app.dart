import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'theme/lumina_theme.dart';

/// Widget raíz de Lumina Player.
/// Gestiona el tema (oscuro/claro) y pasa los callbacks necesarios.
class LuminaApp extends StatefulWidget {
  const LuminaApp({super.key});
  @override
  State<LuminaApp> createState() => _LuminaAppState();
}

class _LuminaAppState extends State<LuminaApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  void _toggleTheme(bool isDark) =>
      setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: buildLuminaTheme(brightness: Brightness.light),
      darkTheme: buildLuminaTheme(brightness: Brightness.dark),
      home: SplashScreen(themeMode: _themeMode, onThemeChanged: _toggleTheme),
    );
  }
}

