import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'equalizer_engine.dart';
import 'playback_transition_settings.dart';

/// Descriptor inmutable de la siguiente pista que debe precargarse o iniciarse
/// en el deck secundario durante un crossfade real sin cortes.
@immutable
final class NextTrackCandidate {
  const NextTrackCandidate({
    required this.actualIndex,
    required this.trackKey,
    required this.uri,
    required this.mediaItem,
  });

  /// Índice real en la lista interna del handler.
  final int actualIndex;

  /// Clave única de la entrada en cola (evita duplicados cuando se repite tema).
  final String trackKey;

  /// URI local o remota resuelta del archivo de audio.
  final Uri uri;

  /// Metadatos de la siguiente pista para publicar al iniciar el cruce.
  final MediaItem mediaItem;
}

/// Motor real de doble deck (ping-pong Deck A ↔ Deck B) para transiciones
/// estilo Spotify **sin ningún corte ni pausa en la canción saliente**.
///
/// Cómo evita cualquier micro-corte:
/// - **Nunca** busca, pausa ni reasigna la canción que está terminando.
/// - Precarga la **siguiente canción** desde `0:00` en el deck en espera unos
///   segundos antes del cruce (con volumen `0.0`).
/// - Al entrar en los últimos `N` segundos, inicia el deck en espera desde
///   `0:00` en silencio (`0.0`), intercambia cuál es el deck activo y aplica
///   la curva equal-power (`cos` bajando en la saliente, `sin` subiendo en la
///   entrante).
/// - Al concluir el cruce, la canción nueva **permanece** en ese mismo deck
///   hasta su propio final: cero traspasos, cero micro-cortes.
final class CrossfadeEngine {
  CrossfadeEngine({
    required EqualizerEngine equalizerEngine,
    required String? Function() resolveCurrentTrackKey,
    required NextTrackCandidate? Function() resolveNextTrack,
    required void Function(NextTrackCandidate next, AudioPlayer newActiveDeck)
    onCrossfadeStarted,
    required Future<void> Function() onActiveTrackCompleted,
    required void Function(AudioPlayer activeDeck) onActiveDeckChanged,
    bool Function()? isCrossfadeSuppressed,
    PlaybackTransitionSettings? settings,
  })  : _equalizerEngine = equalizerEngine,
        _resolveCurrentTrackKey = resolveCurrentTrackKey,
        _resolveNextTrack = resolveNextTrack,
        _onCrossfadeStarted = onCrossfadeStarted,
        _onActiveTrackCompleted = onActiveTrackCompleted,
        _onActiveDeckChanged = onActiveDeckChanged,
        _isCrossfadeSuppressed = isCrossfadeSuppressed,
        _settings = settings ?? PlaybackTransitionSettings.instance {
    final slotA = _equalizerEngine.createDeckPipeline();
    final slotB = _equalizerEngine.createDeckPipeline();
    _slotIndexA = slotA.slotIndex;
    _slotIndexB = slotB.slotIndex;

    _deckA = AudioPlayer(audioPipeline: slotA.pipeline);
    _deckB = AudioPlayer(audioPipeline: slotB.pipeline);

    _bindActiveDeckListeners();
    _settings.crossfadeSeconds.addListener(_onCrossfadeSettingChanged);
  }

  static const Duration _fadeTickInterval = Duration(milliseconds: 35);
  static const Duration _preloadLeadTime = Duration(milliseconds: 3000);
  static const int _minTrackDurationFloorSeconds = 10;

  final EqualizerEngine _equalizerEngine;
  final String? Function() _resolveCurrentTrackKey;
  final NextTrackCandidate? Function() _resolveNextTrack;
  final void Function(NextTrackCandidate next, AudioPlayer newActiveDeck)
  _onCrossfadeStarted;
  final Future<void> Function() _onActiveTrackCompleted;
  final void Function(AudioPlayer activeDeck) _onActiveDeckChanged;
  final bool Function()? _isCrossfadeSuppressed;
  final PlaybackTransitionSettings _settings;

  late final AudioPlayer _deckA;
  late final AudioPlayer _deckB;
  late final int _slotIndexA;
  late final int _slotIndexB;

  int _activeDeckIndex = 0; // 0 = _deckA, 1 = _deckB

  StreamSubscription<Duration>? _activePositionSub;
  StreamSubscription<ProcessingState>? _activeProcessingSub;
  Timer? _crossfadeTimer;

  // Monotónico: cualquier acción manual invalida rampas o crossfades previos.
  int _volumeEpoch = 0;

  // Estado de precarga del deck en espera (para la SIGUIENTE canción).
  String? _preloadedTrackKey;
  Uri? _preloadedTrackUri;
  bool _isPreloading = false;

  // Estado de transición en curso.
  bool _isCrossfading = false;
  bool _isFadingOutToPause = false;
  bool _handlingCompletion = false;
  String? _triggeredFromTrackKey;

  // Ganancias base independientes por deck + factor global del Sleep Timer.
  double _activeBaseVolume = 1.0;
  double _outgoingBaseVolume = 0.0;
  double _sleepTimerFactor = 1.0;
  bool _disposed = false;

  /// Reproductor actualmente visible en UI, barra de progreso y notificación.
  AudioPlayer get activePlayer => _activeDeckIndex == 0 ? _deckA : _deckB;

  /// Reproductor secundario (en espera para precarga o desvaneciendo la pista
  /// saliente durante un crossfade).
  AudioPlayer get standbyPlayer => _activeDeckIndex == 0 ? _deckB : _deckA;

  int get _activeSlotIndex => _activeDeckIndex == 0 ? _slotIndexA : _slotIndexB;
  int get _standbySlotIndex =>
      _activeDeckIndex == 0 ? _slotIndexB : _slotIndexA;

  /// Indica si el crossfade acaba de precargar exactamente [candidate] en el
  /// deck en espera, listo para iniciar al instante.
  bool hasPreloadedCandidate(NextTrackCandidate candidate) =>
      !_isCrossfading &&
      _preloadedTrackKey == candidate.trackKey &&
      _preloadedTrackUri == candidate.uri;

  void _bindActiveDeckListeners() {
    unawaited(_activePositionSub?.cancel());
    unawaited(_activeProcessingSub?.cancel());

    final currentDeck = activePlayer;
    _activePositionSub = currentDeck.positionStream.listen(_onActivePosition);
    _activeProcessingSub = currentDeck.processingStateStream.listen((state) {
      if (_disposed || currentDeck != activePlayer) return;
      if (state == ProcessingState.completed &&
          !_isCrossfading &&
          !_handlingCompletion) {
        _handlingCompletion = true;
        unawaited(
          _onActiveTrackCompleted()
              .catchError((Object e, StackTrace s) {
                debugPrint('Error avanzando al completar pista: $e\n$s');
              })
              .whenComplete(() => _handlingCompletion = false),
        );
      }
    });
  }

  /// Carga una pista en el deck activo para reproducción directa (al tocar una
  /// canción, saltar siguiente/anterior o abrir una playlist) y cancela
  /// limpiamente cualquier crossfade anterior.
  Future<void> loadAndPlayOnActiveDeck(
    Uri uri, {
    required bool autoPlay,
    bool smoothFadeIn = false,
  }) async {
    if (_disposed) return;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    _triggeredFromTrackKey = null;
    _clearPreloadCache();

    await _stopStandbyDeckSafely();
    if (_disposed || epoch != _volumeEpoch) return;

    final deck = activePlayer;
    final useFadeIn =
        autoPlay && smoothFadeIn && _settings.smoothPlayPauseFade.value;
    _activeBaseVolume = useFadeIn ? 0.0 : 1.0;
    await deck.setVolume(_effectiveActiveVolume());
    await deck.setAudioSource(AudioSource.uri(uri), initialPosition: Duration.zero);
    _equalizerEngine.attachDeckSlot(_activeSlotIndex);

    if (_disposed || epoch != _volumeEpoch) return;

    if (autoPlay) {
      unawaited(
        deck.play().catchError((Object e, StackTrace s) {
          debugPrint('Error iniciando reproducción en deck activo: $e\n$s');
        }),
      );
      if (useFadeIn) {
        await _rampActiveVolume(
          from: 0.0,
          to: 1.0,
          duration: PlaybackTransitionSettings.playPauseFadeDuration,
          epoch: epoch,
        );
      }
    }
  }

  /// Intercambia instantáneamente al deck en espera cuando ya tiene precargada
  /// la siguiente pista (usado en cambios naturales con crossfade en `0 s` para
  /// lograr una transición prácticamente sin espacio).
  Future<bool> switchToPreloadedStandby({
    required NextTrackCandidate expected,
    required bool autoPlay,
  }) async {
    if (_disposed || !hasPreloadedCandidate(expected)) return false;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    _triggeredFromTrackKey = null;

    final previousActive = activePlayer;
    final incomingDeck = standbyPlayer;

    _activeDeckIndex = _activeDeckIndex == 0 ? 1 : 0;
    _clearPreloadCache();

    _activeBaseVolume = 1.0;
    await incomingDeck.setVolume(_effectiveActiveVolume());
    await incomingDeck.seek(Duration.zero);

    _bindActiveDeckListeners();
    _onActiveDeckChanged(incomingDeck);

    if (autoPlay && !_disposed && epoch == _volumeEpoch) {
      unawaited(
        incomingDeck.play().catchError((Object e, StackTrace s) {
          debugPrint('Error iniciando deck precargado: $e\n$s');
        }),
      );
    }

    // Detener el deck anterior sin bloquear el inicio del nuevo.
    unawaited(
      previousActive.stop().catchError((Object e, StackTrace s) {
        debugPrint('Error deteniendo deck anterior: $e\n$s');
      }),
    );
    return true;
  }

  /// Invalida la precarga si el usuario reordenó, eliminó o cambió la cola.
  void invalidatePreload() {
    if (_isCrossfading) return;
    _clearPreloadCache();
  }

  void _clearPreloadCache() {
    _preloadedTrackKey = null;
    _preloadedTrackUri = null;
  }

  void _onCrossfadeSettingChanged() {
    if (_disposed) return;
    if (_settings.crossfadeSeconds.value <= 0 && _isCrossfading) {
      unawaited(
        cancelActiveTransition(restoreVolume: true).catchError((
          Object e,
          StackTrace s,
        ) {
          debugPrint('Error cancelando crossfade al desactivar: $e\n$s');
        }),
      );
    }
  }

  void _onActivePosition(Duration position) {
    if (_disposed || _isCrossfading || _isFadingOutToPause) return;

    final deck = activePlayer;
    if (!deck.playing) return;

    final duration = deck.duration;
    if (duration == null || duration <= Duration.zero) return;

    final currentKey = _resolveCurrentTrackKey();
    if (currentKey == null || currentKey.isEmpty) return;

    final crossfadeSecs = _settings.crossfadeSeconds.value;
    final suppressed = _isCrossfadeSuppressed?.call() ?? false;
    final remaining = duration - position;

    // 1. Precargar la SIGUIENTE canción en el deck en espera ~3s antes del
    //    punto de cruce (o 3s antes del final si crossfade == 0).
    //    Esto no toca en absoluto la canción que está sonando.
    final preloadThreshold = Duration(seconds: crossfadeSecs) + _preloadLeadTime;
    if (!suppressed &&
        remaining <= preloadThreshold &&
        remaining > const Duration(milliseconds: 300) &&
        !_isPreloading) {
      final next = _resolveNextTrack();
      if (next != null &&
          (_preloadedTrackKey != next.trackKey ||
              _preloadedTrackUri != next.uri)) {
        unawaited(
          _preloadNextOnStandby(next).catchError((Object e, StackTrace s) {
            debugPrint('Error precargando siguiente pista: $e\n$s');
          }),
        );
      }
    }

    if (crossfadeSecs <= 0 || suppressed) return;

    // Resguardar pistas muy cortas para que no disparen crossfade inmediato.
    final minRequiredSecs = (crossfadeSecs * 2).clamp(
      _minTrackDurationFloorSeconds,
      60,
    );
    if (duration.inSeconds < minRequiredSecs) return;

    final crossfadeDuration = Duration(seconds: crossfadeSecs);

    // Si el usuario retrocedió el scrubber lejos del final, re-armar trigger.
    if (_triggeredFromTrackKey == currentKey &&
        remaining > crossfadeDuration + const Duration(seconds: 2)) {
      _triggeredFromTrackKey = null;
    }

    if (_triggeredFromTrackKey == currentKey) return;

    // 2. Al entrar en los últimos `crossfadeSecs`: iniciar la SIGUIENTE canción
    //    en el deck en espera desde 0:00 con volumen 0.0 mientras la canción
    //    actual sigue sonando SIN INTERRUPCIÓN en su propio deck.
    if (remaining <= crossfadeDuration &&
        remaining > const Duration(milliseconds: 300)) {
      final next = _resolveNextTrack();
      if (next == null) return;

      _triggeredFromTrackKey = currentKey;
      final effectiveFade = remaining < crossfadeDuration
          ? remaining
          : crossfadeDuration;
      unawaited(
        _runTrueDualDeckCrossfade(
          next: next,
          fadeDuration: effectiveFade,
        ).catchError((Object e, StackTrace s) {
          debugPrint('Error ejecutando crossfade dual-deck: $e\n$s');
        }),
      );
    }
  }

  Future<void> _preloadNextOnStandby(NextTrackCandidate candidate) async {
    if (_disposed || _isCrossfading || _isPreloading) return;
    _isPreloading = true;
    try {
      final deck = standbyPlayer;
      final slotIndex = _standbySlotIndex;
      await deck.stop();
      await deck.setVolume(0.0);
      await deck.setAudioSource(
        AudioSource.uri(candidate.uri),
        initialPosition: Duration.zero,
      );
      _equalizerEngine.attachDeckSlot(slotIndex);
      if (_disposed) return;
      _preloadedTrackKey = candidate.trackKey;
      _preloadedTrackUri = candidate.uri;
    } on Exception catch (e, s) {
      debugPrint('Precarga en deck en espera omitida: $e\n$s');
      _clearPreloadCache();
    } finally {
      _isPreloading = false;
    }
  }

  Future<void> _runTrueDualDeckCrossfade({
    required NextTrackCandidate next,
    required Duration fadeDuration,
  }) async {
    if (_disposed || _isCrossfading) return;
    _isCrossfading = true;
    final epoch = ++_volumeEpoch;

    try {
      final outgoingDeck = activePlayer;
      final incomingDeck = standbyPlayer;
      final incomingSlot = _standbySlotIndex;

      // Si el usuario cambió la cola a último momento o no dio tiempo a
      // precargar, cargar la pista entrante AHORA en incomingDeck (en silencio)
      // mientras outgoingDeck sigue sonando sin cortes.
      if (_preloadedTrackKey != next.trackKey ||
          _preloadedTrackUri != next.uri) {
        await incomingDeck.stop();
        await incomingDeck.setVolume(0.0);
        await incomingDeck.setAudioSource(
          AudioSource.uri(next.uri),
          initialPosition: Duration.zero,
        );
        _equalizerEngine.attachDeckSlot(incomingSlot);
      } else {
        await incomingDeck.setVolume(0.0);
        if (incomingDeck.position != Duration.zero) {
          await incomingDeck.seek(Duration.zero);
        }
      }

      if (_disposed || epoch != _volumeEpoch || !outgoingDeck.playing) {
        return;
      }

      // Recalcular el tiempo real restante tras cualquier carga de último
      // segundo para que la curva termine justo cuando acaba la pista saliente.
      final outDuration = outgoingDeck.duration;
      final actualRemaining = (outDuration != null && outDuration > Duration.zero)
          ? outDuration - outgoingDeck.position
          : fadeDuration;
      final effectiveFadeMs =
          (actualRemaining < fadeDuration ? actualRemaining : fadeDuration)
              .inMilliseconds
              .clamp(350, 15000);

      // Arrancar la pista entrante desde 0:00 en silencio absoluto (0.0).
      // La pista saliente NO se pausa, NO se busca y NO se interrumpe jamás.
      _outgoingBaseVolume = _activeBaseVolume;
      _activeBaseVolume = 0.0;
      await incomingDeck.setVolume(0.0);
      unawaited(
        incomingDeck.play().catchError((Object e, StackTrace s) {
          debugPrint('Error iniciando pista entrante en crossfade: $e\n$s');
        }),
      );

      // Promover el deck entrante como deck activo (ping-pong) y avisar a la UI
      // para que muestre la nueva carátula, título y barra desde 0:00.
      _activeDeckIndex = _activeDeckIndex == 0 ? 1 : 0;
      _clearPreloadCache();
      _bindActiveDeckListeners();
      _onActiveDeckChanged(incomingDeck);
      _onCrossfadeStarted(next, incomingDeck);

      // Rampa equal-power suave (coseno bajando saliente, seno subiendo entrante).
      final completer = Completer<void>();
      final stopwatch = Stopwatch()..start();

      _crossfadeTimer?.cancel();
      _crossfadeTimer = Timer.periodic(_fadeTickInterval, (timer) {
        if (_disposed || epoch != _volumeEpoch) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }

        final t = (stopwatch.elapsedMilliseconds / effectiveFadeMs).clamp(
          0.0,
          1.0,
        );
        _outgoingBaseVolume = CrossfadeCurve.outgoingGain(t);
        _activeBaseVolume = CrossfadeCurve.incomingGain(t);

        unawaited(
          _applyDualVolumes(
            activeDeck: incomingDeck,
            outgoingDeck: outgoingDeck,
          ).catchError((Object e, StackTrace s) {
            debugPrint('Error aplicando volumen de crossfade: $e\n$s');
          }),
        );

        if (t >= 1.0) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      });

      await completer.future;

      if (!_disposed && epoch == _volumeEpoch) {
        _activeBaseVolume = 1.0;
        _outgoingBaseVolume = 0.0;
        await incomingDeck.setVolume(_effectiveActiveVolume());
        await _stopDeckSafely(outgoingDeck);
      }
    } on Exception catch (e, s) {
      debugPrint('Error en crossfade dual-deck: $e\n$s');
      if (!_disposed && epoch == _volumeEpoch) {
        _activeBaseVolume = 1.0;
        _outgoingBaseVolume = 0.0;
        await activePlayer.setVolume(_effectiveActiveVolume());
        await _stopStandbyDeckSafely();
      }
    } finally {
      if (epoch == _volumeEpoch) {
        _isCrossfading = false;
      }
    }
  }

  /// Reanuda la reproducción con fundido de entrada suave si está habilitado.
  Future<void> playWithFade() async {
    if (_disposed) return;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    await _stopStandbyDeckSafely();

    final deck = activePlayer;
    if (!_settings.smoothPlayPauseFade.value) {
      _activeBaseVolume = 1.0;
      await deck.setVolume(_effectiveActiveVolume());
      unawaited(
        deck.play().catchError((Object e, StackTrace s) {
          debugPrint('Error en play(): $e\n$s');
        }),
      );
      return;
    }

    // Si ya estaba sonando (p. ej. el usuario canceló una pausa a mitad del
    // fade-out), subimos desde el volumen actual hacia 1.0 sin cortes.
    final startVol = deck.playing ? _activeBaseVolume : 0.0;
    _activeBaseVolume = startVol;
    await deck.setVolume(_effectiveActiveVolume());

    if (!deck.playing) {
      unawaited(
        deck.play().catchError((Object e, StackTrace s) {
          debugPrint('Error iniciando reproducción con fade: $e\n$s');
        }),
      );
    }

    await _rampActiveVolume(
      from: startVol,
      to: 1.0,
      duration: PlaybackTransitionSettings.playPauseFadeDuration,
      epoch: epoch,
    );
  }

  /// Pausa la reproducción con fundido de salida suave si está habilitado.
  ///
  /// Si el usuario pulsa de nuevo durante los ~340 ms de fade-out (doble toque
  /// rápido porque cambió de opinión), cancela la pausa y reanuda suavemente.
  Future<void> pauseWithFade() async {
    if (_disposed) return;
    if (_isFadingOutToPause) {
      await playWithFade();
      return;
    }

    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;

    final deck = activePlayer;
    final outgoing = standbyPlayer;

    if (!_settings.smoothPlayPauseFade.value || !deck.playing) {
      await _stopStandbyDeckSafely();
      await deck.pause();
      if (!_disposed && epoch == _volumeEpoch) {
        _activeBaseVolume = 1.0;
        await deck.setVolume(_effectiveActiveVolume());
      }
      return;
    }

    _isFadingOutToPause = true;
    try {
      final startActive = _activeBaseVolume;
      final startOutgoing = _outgoingBaseVolume;
      final hasOutgoing = outgoing.playing;

      final stopwatch = Stopwatch()..start();
      final totalMs =
          PlaybackTransitionSettings.playPauseFadeDuration.inMilliseconds;

      while (!_disposed && epoch == _volumeEpoch) {
        final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
        _activeBaseVolume = CrossfadeCurve.smoothRamp(startActive, 0.0, t);
        await deck.setVolume(_effectiveActiveVolume());
        if (hasOutgoing) {
          _outgoingBaseVolume = CrossfadeCurve.smoothRamp(
            startOutgoing,
            0.0,
            t,
          );
          await outgoing.setVolume(_effectiveOutgoingVolume());
        }
        if (t >= 1.0) break;
        await Future<void>.delayed(_fadeTickInterval);
      }

      if (_disposed || epoch != _volumeEpoch) return;

      await _stopStandbyDeckSafely();
      await deck.pause();

      // Restaurar ganancia base a 1.0 mientras está en pausa para que cualquier
      // reanudación externa (ej. Bluetooth o sistema) nunca quede muda.
      if (!_disposed && epoch == _volumeEpoch && !deck.playing) {
        _activeBaseVolume = 1.0;
        await deck.setVolume(_effectiveActiveVolume());
      }
    } finally {
      if (epoch == _volumeEpoch) {
        _isFadingOutToPause = false;
      }
    }
  }

  /// Aplica el factor de atenuación `[0.0, 1.0]` enviado por `SleepTimerService`
  /// durante los últimos segundos del temporizador.
  Future<void> setSleepTimerVolumeFactor(double factor) async {
    if (_disposed) return;
    final clamped = factor.clamp(0.0, 1.0);
    if ((_sleepTimerFactor - clamped).abs() < 0.002) return;
    _sleepTimerFactor = clamped;
    await _applyDualVolumes(
      activeDeck: activePlayer,
      outgoingDeck: standbyPlayer,
    );
  }

  /// Pausa la reproducción al concluir la atenuación del Temporizador y
  /// restablece el factor del temporizador a `1.0` de forma segura.
  Future<void> pauseFromSleepTimer() async {
    if (_disposed) return;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    await _stopStandbyDeckSafely();
    await activePlayer.pause();
    if (!_disposed && epoch == _volumeEpoch) {
      _sleepTimerFactor = 1.0;
      _activeBaseVolume = 1.0;
      await activePlayer.setVolume(_effectiveActiveVolume());
    }
  }

  /// Restaura suavemente el volumen si el usuario cancela el Temporizador
  /// mientras ya estaba bajando el volumen.
  Future<void> restoreSleepTimerVolume() async {
    if (_disposed) return;
    if (_sleepTimerFactor >= 0.999) return;
    final startFactor = _sleepTimerFactor;
    final epoch = ++_volumeEpoch;
    const durationMs = 280;
    final stopwatch = Stopwatch()..start();

    while (!_disposed && epoch == _volumeEpoch) {
      final t = (stopwatch.elapsedMilliseconds / durationMs).clamp(0.0, 1.0);
      _sleepTimerFactor = CrossfadeCurve.smoothRamp(startFactor, 1.0, t);
      await _applyDualVolumes(
        activeDeck: activePlayer,
        outgoingDeck: standbyPlayer,
      );
      if (t >= 1.0) break;
      await Future<void>.delayed(_fadeTickInterval);
    }

    if (!_disposed && epoch == _volumeEpoch) {
      _sleepTimerFactor = 1.0;
      await _applyDualVolumes(
        activeDeck: activePlayer,
        outgoingDeck: standbyPlayer,
      );
    }
  }

  /// Cancela inmediatamente cualquier crossfade o rampa en curso (al saltar de
  /// canción manualmente, mover el scrubber o detener la reproducción).
  Future<void> cancelActiveTransition({bool restoreVolume = true}) async {
    if (_disposed) return;
    _volumeEpoch++;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    _triggeredFromTrackKey = null;
    _clearPreloadCache();
    await _stopStandbyDeckSafely();
    if (restoreVolume) {
      _activeBaseVolume = 1.0;
      await activePlayer.setVolume(_effectiveActiveVolume());
    }
  }

  /// Detiene ambos decks por completo.
  Future<void> stopBothDecks() async {
    if (_disposed) return;
    await cancelActiveTransition(restoreVolume: true);
    await activePlayer.stop();
  }

  Future<void> _rampActiveVolume({
    required double from,
    required double to,
    required Duration duration,
    required int epoch,
  }) async {
    final totalMs = duration.inMilliseconds;
    final deck = activePlayer;
    if (totalMs <= 0) {
      _activeBaseVolume = to;
      await deck.setVolume(_effectiveActiveVolume());
      return;
    }

    final stopwatch = Stopwatch()..start();
    while (!_disposed && epoch == _volumeEpoch) {
      final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      _activeBaseVolume = CrossfadeCurve.smoothRamp(from, to, t);
      await deck.setVolume(_effectiveActiveVolume());
      if (t >= 1.0) break;
      await Future<void>.delayed(_fadeTickInterval);
    }
  }

  double _effectiveActiveVolume() =>
      (_activeBaseVolume * _sleepTimerFactor).clamp(0.0, 1.0);

  double _effectiveOutgoingVolume() =>
      (_outgoingBaseVolume * _sleepTimerFactor).clamp(0.0, 1.0);

  Future<void> _applyDualVolumes({
    required AudioPlayer activeDeck,
    required AudioPlayer outgoingDeck,
  }) async {
    if (_disposed) return;
    await activeDeck.setVolume(_effectiveActiveVolume());
    if (outgoingDeck.playing) {
      await outgoingDeck.setVolume(_effectiveOutgoingVolume());
    }
  }

  void _cancelCrossfadeTimerOnly() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
  }

  Future<void> _stopStandbyDeckSafely() async {
    _outgoingBaseVolume = 0.0;
    await _stopDeckSafely(standbyPlayer);
  }

  Future<void> _stopDeckSafely(AudioPlayer deck) async {
    try {
      await deck.stop();
      await deck.setVolume(0.0);
    } on Exception catch (e, s) {
      debugPrint('Error deteniendo deck auxiliar: $e\n$s');
    }
  }

  /// Libera suscripciones, temporizadores y ambos decks de audio.
  Future<void> dispose() async {
    _disposed = true;
    _volumeEpoch++;
    _cancelCrossfadeTimerOnly();
    _settings.crossfadeSeconds.removeListener(_onCrossfadeSettingChanged);
    await _activePositionSub?.cancel();
    await _activeProcessingSub?.cancel();
    _activePositionSub = null;
    _activeProcessingSub = null;
    await _deckA.dispose();
    await _deckB.dispose();
  }
}
