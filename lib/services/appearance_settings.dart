import 'package:flutter/foundation.dart';
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
/// reproductor ya use el estilo correcto.
final class AppearanceSettings {
  AppearanceSettings._();

  /// Instancia única de la app.
  static final AppearanceSettings instance = AppearanceSettings._();

  static const String _kBackgroundStyle = 'player_background_style';
  static const String _kHapticsEnabled = 'haptics_enabled';

  /// Estilo de fondo actual del reproductor; los widgets lo escuchan con
  /// `ValueListenableBuilder` para reconstruir sólo el fondo.
  final ValueNotifier<PlayerBackgroundStyle> backgroundStyle =
      ValueNotifier(PlayerBackgroundStyle.ambient);

  /// Interruptor central de respuesta háptica: único punto que la app
  /// consulta antes de vibrar.
  final ValueNotifier<bool> hapticsEnabled = ValueNotifier(true);

  /// Carga los valores guardados. Seguro de llamar varias veces.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      backgroundStyle.value =
          PlayerBackgroundStyle.parse(prefs.getString(_kBackgroundStyle));
      hapticsEnabled.value = prefs.getBool(_kHapticsEnabled) ?? true;
    } on Exception catch (e, st) {
      // Preferencias ilegibles: se mantienen los valores por defecto.
      debugPrint('AppearanceSettings.load falló: $e\n$st');
    }
  }

  /// Cambia y persiste el estilo de fondo del reproductor.
  Future<void> setBackgroundStyle(PlayerBackgroundStyle style) async {
    if (backgroundStyle.value == style) return;
    backgroundStyle.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackgroundStyle, style.name);
  }

  /// Activa o desactiva la respuesta háptica y lo persiste.
  Future<void> setHapticsEnabled({required bool enabled}) async {
    if (hapticsEnabled.value == enabled) return;
    hapticsEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHapticsEnabled, enabled);
  }
}
