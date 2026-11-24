import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Funciones matemáticas puras para curvas de fundido y crossfade.
///
/// Usa una curva de potencia constante (equal-power: coseno/seno) para que
/// la percepción de volumen se mantenga uniforme durante el solapamiento entre
/// la canción saliente y la entrante, evitando caídas de volumen en el centro.
abstract final class CrossfadeCurve {
  /// Ganancia `[0.0, 1.0]` de la pista saliente en el progreso normalizado [t].
  static double outgoingGain(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return math.cos(clamped * (math.pi / 2.0));
  }

  /// Ganancia `[0.0, 1.0]` de la pista entrante en el progreso normalizado [t].
  static double incomingGain(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return math.sin(clamped * (math.pi / 2.0));
  }

  /// Interpolación suave (smoothstep cúbico) entre [from] y [to] en [t].
  static double smoothRamp(double from, double to, double t) {
    final clamped = t.clamp(0.0, 1.0);
    final eased = clamped * clamped * (3.0 - 2.0 * clamped);
    return (from + (to - from) * eased).clamp(0.0, 1.0);
  }

  /// Calcula el factor de atenuación `[0.0, 1.0]` para el temporizador de
  /// apagado según los milisegundos restantes [remainingMs] y la ventana total
  /// de atenuación [fadeWindowMs].
  static double sleepTimerGain({
    required int remainingMs,
    required int fadeWindowMs,
  }) {
    if (fadeWindowMs <= 0) return 1.0;
    if (remainingMs <= 0) return 0.0;
    if (remainingMs >= fadeWindowMs) return 1.0;
    final progress = remainingMs / fadeWindowMs;
    // Curva cuadrática suave para una caída natural al oído humano.
    return (progress * progress).clamp(0.0, 1.0);
  }
}

/// Preferencias persistidas de transiciones de reproducción (Crossfade estilo
/// Spotify, fundido suave en Play/Pausa y atenuación del Temporizador).
///
/// Debe cargarse con [load] antes de `runApp`, igual que `AppearanceSettings`
/// y `LibraryFilterSettings`.
final class PlaybackTransitionSettings {
  PlaybackTransitionSettings._();

  /// Instancia única de la app.
  static final PlaybackTransitionSettings instance =
      PlaybackTransitionSettings._();

  /// Valor mínimo del slider de crossfade (`0` = desactivado).
  static const int minCrossfadeSeconds = 0;

  /// Valor máximo del slider de crossfade (`12` segundos, rango de Spotify).
  static const int maxCrossfadeSeconds = 12;

  /// Duración del fundido suave al pulsar Play o Pausa.
  static const Duration playPauseFadeDuration = Duration(milliseconds: 340);

  /// Ventana de bajada progresiva de volumen al finalizar el Temporizador.
  static const int sleepTimerFadeSeconds = 10;

  static const String _kCrossfadeSeconds = 'playback_crossfade_seconds';
  static const String _kSmoothPlayPause = 'playback_smooth_play_pause_fade';
  static const String _kSleepTimerFadeOut = 'playback_sleep_timer_fade_out';

  /// Segundos de crossfade entre canciones (`0` = desactivado, `1..12` s).
  final ValueNotifier<int> crossfadeSeconds = ValueNotifier<int>(0);

  /// Si es `true`, atenúa suavemente el volumen al pausar y reanudar.
  final ValueNotifier<bool> smoothPlayPauseFade = ValueNotifier<bool>(true);

  /// Si es `true`, baja el volumen progresivamente en los últimos segundos
  /// del Temporizador (Sleep Timer) en lugar de cortar de golpe.
  final ValueNotifier<bool> sleepTimerFadeOut = ValueNotifier<bool>(true);

  /// Limita cualquier entero al rango válido `[0, 12]`.
  static int clampCrossfadeSeconds(int value) =>
      value.clamp(minCrossfadeSeconds, maxCrossfadeSeconds);

  /// Etiqueta corta para el valor actual de crossfade.
  static String formatCrossfadeLabel(int seconds) {
    final safe = clampCrossfadeSeconds(seconds);
    if (safe == 0) return 'Desactivado';
    return '$safe s';
  }

  /// Resumen compacto para mostrar en el subtítulo de la tarjeta en Ajustes.
  String buildSummary() {
    final cf = crossfadeSeconds.value;
    final parts = <String>[
      if (cf > 0) 'Crossfade $cf s' else 'Crossfade desactivado',
      if (smoothPlayPauseFade.value) 'Fade en pausa',
      if (sleepTimerFadeOut.value) 'Fade en temporizador',
    ];
    return parts.join(' · ');
  }

  /// Carga las preferencias guardadas desde `SharedPreferences`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      crossfadeSeconds.value = clampCrossfadeSeconds(
        prefs.getInt(_kCrossfadeSeconds) ?? 0,
      );
      smoothPlayPauseFade.value = prefs.getBool(_kSmoothPlayPause) ?? true;
      sleepTimerFadeOut.value = prefs.getBool(_kSleepTimerFadeOut) ?? true;
    } on Exception catch (e, st) {
      debugPrint('PlaybackTransitionSettings.load falló: $e\n$st');
    }
  }

  /// Actualiza y persiste la duración del crossfade en segundos (`0..12`).
  Future<void> setCrossfadeSeconds(int seconds) async {
    final clamped = clampCrossfadeSeconds(seconds);
    if (crossfadeSeconds.value == clamped) return;
    crossfadeSeconds.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCrossfadeSeconds, clamped);
    } on Exception catch (e, st) {
      debugPrint('PlaybackTransitionSettings.setCrossfadeSeconds falló: $e\n$st');
    }
  }

  /// Activa o desactiva el fundido suave al pausar y reanudar.
  Future<void> setSmoothPlayPauseFade({required bool enabled}) async {
    if (smoothPlayPauseFade.value == enabled) return;
    smoothPlayPauseFade.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSmoothPlayPause, enabled);
    } on Exception catch (e, st) {
      debugPrint(
        'PlaybackTransitionSettings.setSmoothPlayPauseFade falló: $e\n$st',
      );
    }
  }

  /// Activa o desactiva la bajada progresiva al finalizar el Temporizador.
  Future<void> setSleepTimerFadeOut({required bool enabled}) async {
    if (sleepTimerFadeOut.value == enabled) return;
    sleepTimerFadeOut.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSleepTimerFadeOut, enabled);
    } on Exception catch (e, st) {
      debugPrint(
        'PlaybackTransitionSettings.setSleepTimerFadeOut falló: $e\n$st',
      );
    }
  }
}
