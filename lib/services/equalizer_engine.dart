import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'equalizer_settings.dart';

final class _DeckEffectSlot {
  _DeckEffectSlot({
    required this.pipeline,
    required this.equalizer,
    required this.loudnessEnhancer,
  });

  final AudioPipeline pipeline;
  final AndroidEqualizer? equalizer;
  final AndroidLoudnessEnhancer? loudnessEnhancer;
  AndroidEqualizerParameters? cachedParameters;
  bool parametersWatchStarted = false;
}

/// Motor nativo de ecualización y potenciador de volumen sobre el
/// [AudioPipeline] de `just_audio` (`AndroidEqualizer` + `AndroidLoudnessEnhancer`).
///
/// Soporta múltiples decks (Deck A y Deck B del motor de crossfade dual-deck)
/// manteniendo exactamente la misma curva de ecualización y loudness en ambos
/// reproductores para que el cruce sea tonalmente invisible.
final class EqualizerEngine {
  EqualizerEngine({EqualizerSettings? settings})
    : _settings = settings ?? EqualizerSettings.instance {
    _isAndroidRuntime =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    _settings.enabled.addListener(_scheduleSync);
    _settings.bandLevels.addListener(_scheduleSync);
    _settings.bassBoost.addListener(_scheduleSync);
    _settings.loudnessBoostDb.addListener(_scheduleSync);
  }

  final EqualizerSettings _settings;
  late final bool _isAndroidRuntime;
  final List<_DeckEffectSlot> _slots = [];

  /// Frecuencias centrales reales reportadas por el hardware del teléfono
  /// (por defecto las 5 frecuencias estándar de Android).
  final ValueNotifier<List<double>> centerFrequenciesHz =
      ValueNotifier<List<double>>(EqualizerMath.defaultCenterFrequenciesHz);

  bool _disposed = false;
  bool _syncRunning = false;
  bool _syncPending = false;

  /// Crea y registra un [AudioPipeline] independiente para un deck de audio
  /// (Deck A o Deck B), devolviendo su índice de slot y pipeline.
  ({int slotIndex, AudioPipeline pipeline}) createDeckPipeline() {
    final AndroidEqualizer? eq = _isAndroidRuntime ? AndroidEqualizer() : null;
    final AndroidLoudnessEnhancer? loudness = _isAndroidRuntime
        ? AndroidLoudnessEnhancer()
        : null;
    final pipeline = _isAndroidRuntime
        ? AudioPipeline(androidAudioEffects: [eq!, loudness!])
        : AudioPipeline();

    final slotIndex = _slots.length;
    _slots.add(
      _DeckEffectSlot(
        pipeline: pipeline,
        equalizer: eq,
        loudnessEnhancer: loudness,
      ),
    );
    return (slotIndex: slotIndex, pipeline: pipeline);
  }

  /// Debe llamarse cuando el deck [slotIndex] haya cargado una fuente de audio
  /// para capturar sus bandas reales y sincronizar el estado guardado.
  void attachDeckSlot(int slotIndex) {
    if (_disposed || !_isAndroidRuntime) return;
    if (slotIndex < 0 || slotIndex >= _slots.length) return;

    final slot = _slots[slotIndex];
    final eq = slot.equalizer;
    if (!slot.parametersWatchStarted && eq != null) {
      slot.parametersWatchStarted = true;
      unawaited(
        eq.parameters
            .then((params) {
              if (_disposed) return;
              slot.cachedParameters = params;
              if (params.bands.length == EqualizerSettings.bandCount) {
                centerFrequenciesHz.value = List<double>.unmodifiable(
                  params.bands.map((b) => b.centerFrequency),
                );
              }
              _scheduleSync();
            })
            .catchError((Object e, StackTrace s) {
              debugPrint(
                'Error leyendo parámetros de AndroidEqualizer (slot $slotIndex): $e\n$s',
              );
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
        await _applySettingsToAllSlots();
      }
    } on Exception catch (e, s) {
      debugPrint('Error sincronizando ecualizador con hardware: $e\n$s');
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _applySettingsToAllSlots() async {
    if (_disposed || !_isAndroidRuntime) return;

    final isEnabled = _settings.enabled.value;
    final effectiveFive = _settings.effectiveBandLevels();
    final boostDb = _settings.loudnessBoostDb.value;
    final loudnessActive = isEnabled && boostDb >= 0.1;
    final targetGain = loudnessActive
        ? EqualizerMath.loudnessDbToJustAudioTargetGain(boostDb)
        : 0.0;

    for (final slot in _slots) {
      if (_disposed) return;
      final eq = slot.equalizer;
      if (eq != null) {
        try {
          await eq.setEnabled(isEnabled);
          final params = slot.cachedParameters;
          if (params != null && params.bands.isNotEmpty) {
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

      final loudness = slot.loudnessEnhancer;
      if (loudness != null) {
        try {
          await loudness.setEnabled(loudnessActive);
          await loudness.setTargetGain(targetGain);
        } on Exception catch (e, s) {
          debugPrint('Error aplicando AndroidLoudnessEnhancer: $e\n$s');
        }
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
