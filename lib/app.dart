import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.light,
          primary: const Color(0xFF4CAF50),
          secondary: const Color(0xFF4CAF50),
          surface: const Color(0xFFF5F5F5),
          onSurface: Colors.black87,
        ),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1A1A1A),
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: SplashScreen(themeMode: _themeMode, onThemeChanged: _toggleTheme),
    );
  }
}
