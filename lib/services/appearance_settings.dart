import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estilo visual del fondo del reproductor completo, elegible en Ajustes.
enum PlayerBackgroundStyle {
  /// Degradado fijo con tinte de acento.
  gradient,

  /// Colores tomados de la carátula actual (difuminado ligero, sin blur).
  ambient,

  /// Degradado que va cambiando de color aleatoriamente.
  animated;

  /// Nombre visible en Ajustes.
  String get label => switch (this) {
    PlayerBackgroundStyle.gradient => 'Degradado',
    PlayerBackgroundStyle.ambient => 'Ambiental',
    PlayerBackgroundStyle.animated => 'Dinámico',
  };

  /// Descripción corta para el selector de Ajustes.
  String get description => switch (this) {
    PlayerBackgroundStyle.gradient => 'Fondo fijo elegante',
    PlayerBackgroundStyle.ambient => 'Según la carátula',
    PlayerBackgroundStyle.animated => 'Colores que cambian',
  };

  /// Convierte el valor guardado; un valor desconocido o corrupto cae
  /// explícitamente en [ambient] (nunca en `null`).
  static PlayerBackgroundStyle parse(String? raw) =>
      PlayerBackgroundStyle.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => PlayerBackgroundStyle.ambient,
      );
}

/// Preferencias de apariencia persistidas (singleton, mismo patrón que
/// `SleepTimerService`).
///
/// Debe cargarse con [load] ANTES de `runApp` para que el primer frame del
/// reproductor ya use el tema y el estilo correcto.
final class AppearanceSettings {
  AppearanceSettings._();

  /// Instancia única de la app.
  static final AppearanceSettings instance = AppearanceSettings._();

  static const String _kBackgroundStyle = 'player_background_style';
  static const String _kHapticsEnabled = 'haptics_enabled';
  static const String _kThemeMode = 'app_theme_mode';

  /// Modo de tema persistido (oscuro por defecto).
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);

  /// Estilo de fondo actual del reproductor; los widgets lo escuchan con
  /// `ValueListenableBuilder` para reconstruir sólo el fondo.
  final ValueNotifier<PlayerBackgroundStyle> backgroundStyle = ValueNotifier(
    PlayerBackgroundStyle.ambient,
  );

  /// Interruptor central de respuesta háptica: único punto que la app
  /// consulta antes de vibrar.
  final ValueNotifier<bool> hapticsEnabled = ValueNotifier(true);

  static ThemeMode _parseThemeMode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.dark,
  };

  /// Carga los valores guardados. Seguro de llamar varias veces.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      themeMode.value = _parseThemeMode(prefs.getString(_kThemeMode));
      backgroundStyle.value = PlayerBackgroundStyle.parse(
        prefs.getString(_kBackgroundStyle),
      );
      hapticsEnabled.value = prefs.getBool(_kHapticsEnabled) ?? true;
    } on Exception catch (e, st) {
      // Preferencias ilegibles: se mantienen los valores por defecto.
      debugPrint('AppearanceSettings.load falló: $e\n$st');
    }
  }

  /// Cambia y persiste el modo de tema (claro / oscuro).
  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kThemeMode,
        mode == ThemeMode.light ? 'light' : 'dark',
      );
    } on Exception catch (e, st) {
      debugPrint('AppearanceSettings.setThemeMode falló: $e\n$st');
    }
  }

  /// Cambia y persiste el estilo de fondo del reproductor.
  Future<void> setBackgroundStyle(PlayerBackgroundStyle style) async {
    if (backgroundStyle.value == style) return;
    backgroundStyle.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBackgroundStyle, style.name);
    } on Exception catch (e, st) {
      debugPrint('AppearanceSettings.setBackgroundStyle falló: $e\n$st');
    }
  }

  /// Activa o desactiva la respuesta háptica y lo persiste.
  Future<void> setHapticsEnabled({required bool enabled}) async {
    if (hapticsEnabled.value == enabled) return;
    hapticsEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHapticsEnabled, enabled);
    } on Exception catch (e, st) {
      debugPrint('AppearanceSettings.setHapticsEnabled falló: $e\n$st');
    }
  }
}
