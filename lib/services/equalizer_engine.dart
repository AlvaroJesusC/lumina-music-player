import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'equalizer_settings.dart';

/// Motor nativo de ecualización y potenciador de volumen sobre el
/// [AudioPipeline] de `just_audio` (`AndroidEqualizer` + `AndroidLoudnessEnhancer`).
///
/// Escucha [EqualizerSettings] y sincroniza cada cambio en tiempo real con el
/// hardware de Android de forma segura (sin bloquear ni fallar en plataformas
/// no Android o antes de que se cargue la primera pista).
final class EqualizerEngine {
  EqualizerEngine({EqualizerSettings? settings})
    : _settings = settings ?? EqualizerSettings.instance {
    _isAndroidRuntime =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (_isAndroidRuntime) {
      _equalizer = AndroidEqualizer();
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      pipeline = AudioPipeline(
        androidAudioEffects: [_equalizer!, _loudnessEnhancer!],
      );
    } else {
      _equalizer = null;
      _loudnessEnhancer = null;
      pipeline = AudioPipeline();
    }

    _settings.enabled.addListener(_scheduleSync);
    _settings.bandLevels.addListener(_scheduleSync);
    _settings.bassBoost.addListener(_scheduleSync);
    _settings.loudnessBoostDb.addListener(_scheduleSync);
  }

  final EqualizerSettings _settings;
  late final bool _isAndroidRuntime;
  late final AndroidEqualizer? _equalizer;
  late final AndroidLoudnessEnhancer? _loudnessEnhancer;

  /// Pipeline que debe entregarse al constructor de `AudioPlayer`.
  late final AudioPipeline pipeline;

  /// Frecuencias centrales reales reportadas por el hardware del teléfono
  /// (por defecto las 5 frecuencias estándar de Android).
  final ValueNotifier<List<double>> centerFrequenciesHz =
      ValueNotifier<List<double>>(EqualizerMath.defaultCenterFrequenciesHz);

  AndroidEqualizerParameters? _cachedParameters;
  bool _parametersWatchStarted = false;
  bool _disposed = false;
  bool _syncRunning = false;
  bool _syncPending = false;

  /// Debe llamarse una vez que `AudioPlayer.setAudioSource(...)` haya activado
  /// el motor nativo para leer las bandas reales y aplicar el estado guardado.
  void attachToActivePlayer() {
    if (_disposed || !_isAndroidRuntime) return;

    if (!_parametersWatchStarted && _equalizer != null) {
      _parametersWatchStarted = true;
      unawaited(
        _equalizer.parameters
            .then((params) {
              if (_disposed) return;
              _cachedParameters = params;
              if (params.bands.length == EqualizerSettings.bandCount) {
                centerFrequenciesHz.value = List<double>.unmodifiable(
                  params.bands.map((b) => b.centerFrequency),
                );
              }
              _scheduleSync();
            })
            .catchError((Object e, StackTrace s) {
              debugPrint('Error leyendo parámetros de AndroidEqualizer: $e\n$s');
            }),
      );
    }

    _scheduleSync();
  }

  /// Coalesce múltiples eventos rápidos de arrastre de sliders en un solo bucle
  /// de sincronización para evitar acumulación de llamadas nativas (lag).
  void _scheduleSync() {
    if (_disposed || !_isAndroidRuntime) return;
    _syncPending = true;
    if (_syncRunning) return;
    unawaited(_drainSyncLoop());
  }

  Future<void> _drainSyncLoop() async {
    _syncRunning = true;
    try {
      while (!_disposed && _syncPending) {
        _syncPending = false;
        await _applySettingsToHardware();
      }
    } on Exception catch (e, s) {
      debugPrint('Error sincronizando ecualizador con hardware: $e\n$s');
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _applySettingsToHardware() async {
    if (_disposed || !_isAndroidRuntime) return;

    final eq = _equalizer;
    final loudness = _loudnessEnhancer;
    final isEnabled = _settings.enabled.value;

    if (eq != null) {
      try {
        await eq.setEnabled(isEnabled);
        final params = _cachedParameters;
        if (params != null && params.bands.isNotEmpty) {
          final effectiveFive = _settings.effectiveBandLevels();
          final deviceLevels = EqualizerMath.resampleNormalizedBands(
            effectiveFive,
            params.bands.length,
          );
          for (var i = 0; i < params.bands.length; i++) {
            final gain = EqualizerMath.mapNormalizedToDeviceGain(
              normalized: deviceLevels[i],
              minDevice: params.minDecibels,
              maxDevice: params.maxDecibels,
            );
            await params.bands[i].setGain(gain);
          }
        }
      } on Exception catch (e, s) {
        debugPrint('Error aplicando bandas de AndroidEqualizer: $e\n$s');
      }
    }

    if (loudness != null) {
      try {
        final boostDb = _settings.loudnessBoostDb.value;
        final loudnessActive = isEnabled && boostDb >= 0.1;
        await loudness.setEnabled(loudnessActive);
        final targetGain = loudnessActive
            ? EqualizerMath.loudnessDbToJustAudioTargetGain(boostDb)
            : 0.0;
        await loudness.setTargetGain(targetGain);
      } on Exception catch (e, s) {
        debugPrint('Error aplicando AndroidLoudnessEnhancer: $e\n$s');
      }
    }
  }

  /// Libera los listeners del motor de ecualización.
  void dispose() {
    _disposed = true;
    _settings.enabled.removeListener(_scheduleSync);
    _settings.bandLevels.removeListener(_scheduleSync);
    _settings.bassBoost.removeListener(_scheduleSync);
    _settings.loudnessBoostDb.removeListener(_scheduleSync);
    centerFrequenciesHz.dispose();
  }
}
