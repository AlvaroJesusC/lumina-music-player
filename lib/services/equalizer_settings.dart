import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presets predefinidos de ecualización con 5 bandas normalizadas en `[-1.0, 1.0]`.
///
/// Las bandas corresponden a las 5 frecuencias típicas de Android:
/// `[60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz]`.
enum EqualizerPreset {
  /// Sin modificaciones (sonido original).
  flat('Plano', Icons.horizontal_rule_rounded, [0.0, 0.0, 0.0, 0.0, 0.0]),

  /// Refuerzo marcado de sub-graves y graves medios.
  bassBoost('Graves+', Icons.speaker_rounded, [0.75, 0.45, 0.0, 0.05, 0.15]),

  /// Curva equilibrada con ligero brillo y presencia.
  pop('Pop', Icons.auto_awesome_rounded, [0.20, 0.40, 0.15, 0.30, 0.35]),

  /// Graves con pegada y agudos definidos para guitarras/platillos.
  rock('Rock', Icons.electric_bolt_rounded, [0.50, 0.25, -0.15, 0.35, 0.55]),

  /// Sub-graves potentes y brillo cristalino.
  electronic(
    'Electrónica',
    Icons.graphic_eq_rounded,
    [0.65, 0.30, -0.10, 0.35, 0.60],
  ),

  /// Resalta frecuencias vocales y limpia graves excesivos.
  vocal('Vocal', Icons.mic_none_rounded, [-0.25, 0.05, 0.55, 0.45, 0.15]),

  /// Calidez suave y claridad en instrumentos acústicos.
  classical('Clásica', Icons.piano_rounded, [0.35, 0.20, -0.05, 0.25, 0.45]),

  /// Curva editada manualmente por el usuario.
  custom('Personalizado', Icons.tune_rounded, [0.0, 0.0, 0.0, 0.0, 0.0]);

  const EqualizerPreset(this.label, this.icon, this.bands);

  /// Nombre visible en la UI.
  final String label;

  /// Icono representativo del preset.
  final IconData icon;

  /// Niveles normalizados `[-1.0, +1.0]` de las 5 bandas.
  final List<double> bands;

  /// Convierte un nombre guardado; ante valores desconocidos cae en [flat].
  static EqualizerPreset parse(String? raw) => EqualizerPreset.values.firstWhere(
    (p) => p.name == raw,
    orElse: () => EqualizerPreset.flat,
  );
}

/// Utilidades matemáticas puras para mapear valores de ecualizador y loudness
/// al hardware de Android sin riesgo de desbordamiento ni saturación.
abstract final class EqualizerMath {
  /// Frecuencias centrales de referencia (Hz) cuando el dispositivo aún no
  /// reporta parámetros de hardware.
  static const List<double> defaultCenterFrequenciesHz = [
    60.0,
    230.0,
    910.0,
    3600.0,
    14000.0,
  ];

  /// Escala visual en dB usada para las etiquetas de cada banda en la UI.
  static const double displayMaxDb = 12.0;

  /// Ganancia máxima segura en dB para el potenciador de volumen (Loudness).
  static const double maxLoudnessBoostDb = 10.0;

  /// Mapea una ganancia normalizada `[-1.0, 1.0]` al rango real reportado por
  /// `AndroidEqualizerParameters` (`[minDevice, maxDevice]`).
  ///
  /// Esto protege contra la convención de `just_audio` en Android (donde
  /// `±1500 mB` se expone como `±1.5`) y ante cualquier rango asimétrico.
  static double mapNormalizedToDeviceGain({
    required double normalized,
    required double minDevice,
    required double maxDevice,
  }) {
    final safe = normalized.clamp(-1.0, 1.0);
    if (safe >= 0.0) {
      return (safe * maxDevice).clamp(minDevice, maxDevice);
    }
    return (-safe * minDevice).clamp(minDevice, maxDevice);
  }

  /// Convierte el refuerzo de volumen en dB (`0..10 dB`) a la unidad esperada
  /// por `AndroidLoudnessEnhancer.setTargetGain` en `just_audio`
  /// (`targetGain * 1000 = millibels`, donde `100 mB = 1 dB` ⇒ `10 dB = 1.0`).
  static double loudnessDbToJustAudioTargetGain(double boostDb) {
    final clampedDb = boostDb.clamp(0.0, maxLoudnessBoostDb);
    return clampedDb / 10.0;
  }

  /// Remuestrea una curva de 5 bandas a cualquier número de bandas de hardware
  /// [targetBandCount] mediante interpolación lineal.
  static List<double> resampleNormalizedBands(
    List<double> sourceBands,
    int targetBandCount,
  ) {
    if (targetBandCount <= 0) return const [];
    if (sourceBands.isEmpty) {
      return List<double>.filled(targetBandCount, 0.0);
    }
    if (targetBandCount == sourceBands.length) {
      return sourceBands.map((v) => v.clamp(-1.0, 1.0)).toList();
    }
    if (targetBandCount == 1) {
      final mid = sourceBands[sourceBands.length ~/ 2];
      return [mid.clamp(-1.0, 1.0)];
    }

    final result = <double>[];
    final maxSrcIdx = sourceBands.length - 1;
    for (var i = 0; i < targetBandCount; i++) {
      final pos = (i / (targetBandCount - 1)) * maxSrcIdx;
      final lower = pos.floor();
      final upper = pos.ceil();
      final frac = pos - lower;
      final interpolated =
          sourceBands[lower] + (sourceBands[upper] - sourceBands[lower]) * frac;
      result.add(interpolated.clamp(-1.0, 1.0));
    }
    return result;
  }

  /// Aplica el refuerzo extra de graves (`bassBoost` en `0.0..1.0`) sobre la
  /// banda [bandIndex] dentro de un ecualizador de 5 bandas, acotando a `1.0`.
  static double applyBassBoostToBand({
    required double baseNormalized,
    required int bandIndex,
    required double bassBoost,
  }) {
    final safeBass = bassBoost.clamp(0.0, 1.0);
    final extra = switch (bandIndex) {
      0 => safeBass * 0.65,
      1 => safeBass * 0.35,
      _ => 0.0,
    };
    return (baseNormalized + extra).clamp(-1.0, 1.0);
  }

  /// Formatea una frecuencia en Hz a etiqueta legible (`60 Hz`, `3.6 kHz`).
  static String formatFrequency(double hz) {
    if (hz >= 1000.0) {
      final khz = hz / 1000.0;
      final formatted = khz >= 10.0 || (khz - khz.round()).abs() < 0.05
          ? khz.round().toString()
          : khz.toStringAsFixed(1);
      return '$formatted kHz';
    }
    return '${hz.round()} Hz';
  }

  /// Formatea una ganancia normalizada `[-1.0, 1.0]` a dB legibles (`+4 dB`).
  static String formatNormalizedDb(double normalized) {
    final db = (normalized.clamp(-1.0, 1.0) * displayMaxDb).round();
    if (db > 0) return '+$db dB';
    return '$db dB';
  }
}

/// Preferencias persistidas del Ecualizador nativo, Refuerzo de graves y
/// Potenciador de volumen (Loudness).
///
/// Debe cargarse con [load] antes de `runApp`, siguiendo el mismo patrón que
/// `AppearanceSettings` y `PlaybackTransitionSettings`.
final class EqualizerSettings {
  EqualizerSettings._();

  /// Instancia única de la app.
  static final EqualizerSettings instance = EqualizerSettings._();

  /// Número estándar de bandas del ecualizador en la interfaz.
  static const int bandCount = 5;

  static const String _kEnabled = 'eq_enabled';
  static const String _kPreset = 'eq_preset';
  static const String _kBands = 'eq_bands_json';
  static const String _kBassBoost = 'eq_bass_boost';
  static const String _kLoudnessDb = 'eq_loudness_db';

  /// Interruptor maestro del ecualizador y efectos.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Preset activo (`flat`, `bassBoost`, `pop`, `rock`, `custom`, etc.).
  final ValueNotifier<EqualizerPreset> preset = ValueNotifier<EqualizerPreset>(
    EqualizerPreset.flat,
  );

  /// Niveles base de las 5 bandas en rango normalizado `[-1.0, +1.0]`.
  final ValueNotifier<List<double>> bandLevels = ValueNotifier<List<double>>(
    const [0.0, 0.0, 0.0, 0.0, 0.0],
  );

  /// Refuerzo adicional de graves (`0.0` = sin refuerzo, `1.0` = máximo).
  final ValueNotifier<double> bassBoost = ValueNotifier<double>(0.0);

  /// Potenciador de volumen en dB (`0.0` .. `10.0` dB).
  final ValueNotifier<double> loudnessBoostDb = ValueNotifier<double>(0.0);

  /// Ganancia normalizada efectiva (base + Bass Boost) para la banda [index].
  double effectiveBandLevel(int index) {
    final levels = bandLevels.value;
    if (index < 0 || index >= levels.length) return 0.0;
    return EqualizerMath.applyBassBoostToBand(
      baseNormalized: levels[index],
      bandIndex: index,
      bassBoost: bassBoost.value,
    );
  }

  /// Lista de las 5 ganancias efectivas normalizadas (incluyendo Bass Boost).
  List<double> effectiveBandLevels() {
    return List<double>.generate(bandCount, effectiveBandLevel);
  }

  /// Indica si existe algún ajuste distinto al estado plano inicial.
  bool get hasCustomModifications {
    if (preset.value != EqualizerPreset.flat) return true;
    if (bassBoost.value > 0.01) return true;
    if (loudnessBoostDb.value > 0.05) return true;
    return bandLevels.value.any((v) => v.abs() > 0.01);
  }

  /// Resumen compacto para mostrar en Ajustes.
  String buildSummary() {
    if (!enabled.value) return 'Desactivado';
    final parts = <String>[preset.value.label];
    if (bassBoost.value >= 0.05) {
      parts.add('Graves +${(bassBoost.value * 100).round()}%');
    }
    if (loudnessBoostDb.value >= 0.5) {
      parts.add('Volumen +${loudnessBoostDb.value.round()} dB');
    }
    return parts.join(' · ');
  }

  /// Carga la configuración guardada desde `SharedPreferences`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_kEnabled) ?? false;
      preset.value = EqualizerPreset.parse(prefs.getString(_kPreset));
      bassBoost.value = (prefs.getDouble(_kBassBoost) ?? 0.0).clamp(0.0, 1.0);
      loudnessBoostDb.value = (prefs.getDouble(_kLoudnessDb) ?? 0.0).clamp(
        0.0,
        EqualizerMath.maxLoudnessBoostDb,
      );

      final rawBands = prefs.getString(_kBands);
      if (rawBands != null && rawBands.isNotEmpty) {
        final decoded = jsonDecode(rawBands);
        if (decoded is List && decoded.length == bandCount) {
          bandLevels.value = List<double>.unmodifiable(
            decoded.map((e) => (e as num).toDouble().clamp(-1.0, 1.0)),
          );
          return;
        }
      }
      bandLevels.value = List<double>.unmodifiable(preset.value.bands);
    } on Exception catch (e, st) {
      debugPrint('EqualizerSettings.load falló: $e\n$st');
    }
  }

  /// Activa o desactiva el ecualizador y lo persiste.
  Future<void> setEnabled({required bool enabled}) async {
    if (this.enabled.value == enabled) return;
    this.enabled.value = enabled;
    await _persistAll();
  }

  /// Aplica un preset predefinido y activa el ecualizador automáticamente si
  /// no es [EqualizerPreset.flat].
  Future<void> applyPreset(EqualizerPreset newPreset) async {
    preset.value = newPreset;
    if (newPreset != EqualizerPreset.custom) {
      bandLevels.value = List<double>.unmodifiable(newPreset.bands);
    }
    if (newPreset != EqualizerPreset.flat && !enabled.value) {
      enabled.value = true;
    }
    await _persistAll();
  }

  /// Actualiza una banda individual (`0..4`) en rango `[-1.0, +1.0]` y cambia
  /// el preset a [EqualizerPreset.custom].
  ///
  /// Con [persist] en `false` aplica el cambio al instante en memoria/hardware
  /// durante un arrastre del slider sin escribir a disco en cada frame; llama
  /// luego a [persist] en `onChangeEnd`.
  Future<void> setBandLevel(
    int index,
    double normalized, {
    bool persist = true,
  }) async {
    if (index < 0 || index >= bandCount) return;
    final clamped = normalized.clamp(-1.0, 1.0);
    final updated = List<double>.from(bandLevels.value);
    if ((updated[index] - clamped).abs() < 0.001 &&
        preset.value == EqualizerPreset.custom) {
      if (persist) await _persistAll();
      return;
    }
    updated[index] = clamped;
    bandLevels.value = List<double>.unmodifiable(updated);
    preset.value = EqualizerPreset.custom;
    if (!enabled.value) {
      enabled.value = true;
    }
    if (persist) await _persistAll();
  }

  /// Actualiza el refuerzo adicional de graves (`0.0..1.0`).
  Future<void> setBassBoost(double amount, {bool persist = true}) async {
    final clamped = amount.clamp(0.0, 1.0);
    if ((bassBoost.value - clamped).abs() < 0.001) {
      if (persist) await _persistAll();
      return;
    }
    bassBoost.value = clamped;
    if (clamped > 0.01 && !enabled.value) {
      enabled.value = true;
    }
    if (persist) await _persistAll();
  }

  /// Actualiza la ganancia extra del potenciador de volumen (`0..10 dB`).
  Future<void> setLoudnessBoostDb(double db, {bool persist = true}) async {
    final clamped = db.clamp(0.0, EqualizerMath.maxLoudnessBoostDb);
    if ((loudnessBoostDb.value - clamped).abs() < 0.05) {
      if (persist) await _persistAll();
      return;
    }
    loudnessBoostDb.value = clamped;
    if (clamped >= 0.5 && !enabled.value) {
      enabled.value = true;
    }
    if (persist) await _persistAll();
  }

  /// Guarda explícitamente el estado actual en `SharedPreferences`.
  Future<void> persist() => _persistAll();

  /// Restablece bandas, graves y potenciador al perfil plano original.
  Future<void> reset() async {
    preset.value = EqualizerPreset.flat;
    bandLevels.value = List<double>.unmodifiable(EqualizerPreset.flat.bands);
    bassBoost.value = 0.0;
    loudnessBoostDb.value = 0.0;
    await _persistAll();
  }

  Future<void> _persistAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, enabled.value);
      await prefs.setString(_kPreset, preset.value.name);
      await prefs.setString(_kBands, jsonEncode(bandLevels.value));
      await prefs.setDouble(_kBassBoost, bassBoost.value);
      await prefs.setDouble(_kLoudnessDb, loudnessBoostDb.value);
    } on Exception catch (e, st) {
      debugPrint('EqualizerSettings._persistAll falló: $e\n$st');
    }
  }
}
