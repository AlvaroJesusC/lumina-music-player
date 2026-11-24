import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_transition_settings.dart';

/// Motor desacoplado de transiciones suaves de audio para Lumina Player.
///
/// Gestiona tres comportamientos sin ensuciar `MyAudioHandler`:
/// 1. **Crossfade real estilo Spotify:** Solapa los últimos `N` segundos de la
///    canción saliente con el inicio de la siguiente usando un reproductor
///    auxiliar silencioso respecto al foco de audio del sistema
///    (`handleAudioSessionActivation: false`, `handleInterruptions: false`) y
///    una curva equal-power (coseno/seno).
/// 2. **Fundido suave en Play/Pausa:** Atenúa el volumen antes de pausar y lo
///    eleva gradualmente al reanudar, cancelándose limpiamente si el usuario
///    pulsa rápido varias veces.
/// 3. **Atenuación progresiva del Temporizador (Sleep Timer):** Multiplica la
///    ganancia final por el factor del temporizador para bajar suavemente el
///    volumen durante los últimos segundos antes de detener la música.
final class CrossfadeEngine {
  CrossfadeEngine({
    required AudioPlayer primaryPlayer,
    required Uri? Function() resolveCurrentTrackUri,
    required String? Function() resolveCurrentTrackKey,
    required bool Function() canAdvanceToNext,
    required Future<void> Function() advanceToNext,
    bool Function()? isCrossfadeSuppressed,
    PlaybackTransitionSettings? settings,
  })  : _primaryPlayer = primaryPlayer,
        _resolveCurrentTrackUri = resolveCurrentTrackUri,
        _resolveCurrentTrackKey = resolveCurrentTrackKey,
        _canAdvanceToNext = canAdvanceToNext,
        _advanceToNext = advanceToNext,
        _isCrossfadeSuppressed = isCrossfadeSuppressed,
        _settings = settings ?? PlaybackTransitionSettings.instance {
    _positionSub = _primaryPlayer.positionStream.listen(_onPrimaryPosition);
    _settings.crossfadeSeconds.addListener(_onCrossfadeSettingChanged);
  }

  static const Duration _fadeTickInterval = Duration(milliseconds: 40);
  static const Duration _preloadLeadTime = Duration(milliseconds: 2500);
  static const int _minTrackDurationFloorSeconds = 10;

  final AudioPlayer _primaryPlayer;
  final Uri? Function() _resolveCurrentTrackUri;
  final String? Function() _resolveCurrentTrackKey;
  final bool Function() _canAdvanceToNext;
  final Future<void> Function() _advanceToNext;
  final bool Function()? _isCrossfadeSuppressed;
  final PlaybackTransitionSettings _settings;

  AudioPlayer? _outgoingPlayer;
  StreamSubscription<Duration>? _positionSub;
  Timer? _crossfadeTimer;

  // Monotónico: cualquier cambio de volumen/estado invalida rampas anteriores.
  int _volumeEpoch = 0;

  // Estado de precarga y transición para evitar disparos duplicados por pista.
  String? _preloadedTrackKey;
  Uri? _preloadedTrackUri;
  bool _isPreloading = false;
  bool _isCrossfading = false;
  bool _isFadingOutToPause = false;
  String? _triggeredTrackKey;

  // Ganancias independientes combinadas al aplicar volumen en _primaryPlayer.
  double _primaryBaseVolume = 1.0;
  double _outgoingBaseVolume = 0.0;
  double _sleepTimerFactor = 1.0;
  bool _disposed = false;

  /// Crea bajo demanda el deck auxiliar sin interferir con el AudioFocus ni
  /// las interrupciones del sistema (de las que se encarga [_primaryPlayer]).
  AudioPlayer _ensureOutgoingPlayer() {
    return _outgoingPlayer ??= AudioPlayer(
      handleInterruptions: false,
      androidApplyAudioAttributes: false,
      handleAudioSessionActivation: false,
    );
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

  void _onPrimaryPosition(Duration position) {
    if (_disposed || _isCrossfading || _isFadingOutToPause) return;

    final crossfadeSecs = _settings.crossfadeSeconds.value;
    if (crossfadeSecs <= 0) return;
    if (_isCrossfadeSuppressed?.call() ?? false) return;
    if (!_primaryPlayer.playing) return;
    if (!_canAdvanceToNext()) return;

    final duration = _primaryPlayer.duration;
    if (duration == null || duration <= Duration.zero) return;

    // Resguardar pistas muy cortas para que no disparen crossfade inmediato.
    final minRequiredSecs = (crossfadeSecs * 2).clamp(
      _minTrackDurationFloorSeconds,
      60,
    );
    if (duration.inSeconds < minRequiredSecs) return;

    final trackKey = _resolveCurrentTrackKey();
    if (trackKey == null || trackKey.isEmpty) return;

    // Si el usuario retrocedió la barra lejos del final, permitir nuevo trigger.
    final crossfadeDuration = Duration(seconds: crossfadeSecs);
    final remaining = duration - position;
    if (_triggeredTrackKey == trackKey &&
        remaining > crossfadeDuration + const Duration(seconds: 2)) {
      _triggeredTrackKey = null;
    }

    if (_triggeredTrackKey == trackKey) return;

    // 1. Precargar el archivo actual en el deck saliente ~2.5s antes del cruce
    //    para que el traspaso de audio sea instantáneo sin latencia de lectura.
    if (remaining <= crossfadeDuration + _preloadLeadTime &&
        remaining > crossfadeDuration &&
        _preloadedTrackKey != trackKey &&
        !_isPreloading) {
      final uri = _resolveCurrentTrackUri();
      if (uri != null && uri.toString().isNotEmpty) {
        unawaited(
          _preloadOutgoingTrack(trackKey, uri).catchError((
            Object e,
            StackTrace s,
          ) {
            debugPrint('Error precargando pista saliente para crossfade: $e\n$s');
          }),
        );
      }
    }

    // 2. Iniciar crossfade cuando entramos en los últimos `crossfadeSecs`.
    if (remaining <= crossfadeDuration &&
        remaining > const Duration(milliseconds: 250)) {
      _triggeredTrackKey = trackKey;
      final effectiveFade = remaining < crossfadeDuration
          ? remaining
          : crossfadeDuration;
      unawaited(
        _runCrossfade(
          outgoingTrackKey: trackKey,
          fadeDuration: effectiveFade,
        ).catchError((Object e, StackTrace s) {
          debugPrint('Error durante crossfade: $e\n$s');
        }),
      );
    }
  }

  Future<void> _preloadOutgoingTrack(String trackKey, Uri uri) async {
    if (_disposed || _isCrossfading) return;
    _isPreloading = true;
    try {
      final deck = _ensureOutgoingPlayer();
      await deck.stop();
      await deck.setVolume(0.0);
      await deck.setAudioSource(AudioSource.uri(uri));
      if (_disposed) return;
      _preloadedTrackKey = trackKey;
      _preloadedTrackUri = uri;
    } on Exception catch (e, s) {
      debugPrint('Precarga de crossfade omitida: $e\n$s');
      _preloadedTrackKey = null;
      _preloadedTrackUri = null;
    } finally {
      _isPreloading = false;
    }
  }

  Future<void> _runCrossfade({
    required String outgoingTrackKey,
    required Duration fadeDuration,
  }) async {
    if (_disposed || _isCrossfading) return;
    _isCrossfading = true;
    final epoch = ++_volumeEpoch;

    try {
      final uri = _resolveCurrentTrackUri();
      final handoffReady = await _prepareOutgoingDeckForHandoff(
        outgoingTrackKey: outgoingTrackKey,
        uri: uri,
      );

      if (_disposed || epoch != _volumeEpoch || !_primaryPlayer.playing) {
        _isCrossfading = false;
        return;
      }

      if (handoffReady) {
        await _executeDualDeckCrossfade(
          fadeDuration: fadeDuration,
          epoch: epoch,
        );
      } else {
        await _executeFallbackSingleDeckFade(
          fadeDuration: fadeDuration,
          epoch: epoch,
        );
      }
    } finally {
      if (epoch == _volumeEpoch) {
        _isCrossfading = false;
      }
    }
  }

  Future<bool> _prepareOutgoingDeckForHandoff({
    required String outgoingTrackKey,
    required Uri? uri,
  }) async {
    if (uri == null || uri.toString().isEmpty) return false;
    try {
      final deck = _ensureOutgoingPlayer();
      if (_preloadedTrackKey != outgoingTrackKey || _preloadedTrackUri != uri) {
        await deck.stop();
        await deck.setVolume(0.0);
        await deck.setAudioSource(AudioSource.uri(uri));
        _preloadedTrackKey = outgoingTrackKey;
        _preloadedTrackUri = uri;
      }
      final handoffPos = _primaryPlayer.position;
      await deck.seek(handoffPos);
      return true;
    } on Exception catch (e, s) {
      debugPrint('Fallback de crossfade activado: $e\n$s');
      return false;
    }
  }

  Future<void> _executeDualDeckCrossfade({
    required Duration fadeDuration,
    required int epoch,
  }) async {
    final deck = _outgoingPlayer;
    if (deck == null) return;

    // Arrancar la pista saliente exactamente donde iba y mutear el deck
    // principal justo antes de avanzar a la siguiente canción.
    _outgoingBaseVolume = 1.0;
    await deck.setVolume(_effectiveOutgoingVolume());
    // No hacemos await de deck.play() porque `just_audio.play()` completa al
    // finalizar la reproducción, no al iniciar.
    unawaited(
      deck.play().catchError((Object e, StackTrace s) {
        debugPrint('Error reproduciendo deck saliente: $e\n$s');
      }),
    );

    _primaryBaseVolume = 0.0;
    await _applyPrimaryVolume();
    await _advanceToNext();

    if (_disposed || epoch != _volumeEpoch) {
      await _stopOutgoingDeckSafely();
      return;
    }

    if (!_primaryPlayer.playing) {
      unawaited(
        _primaryPlayer.play().catchError((Object e, StackTrace s) {
          debugPrint('Error reanudando pista entrante en crossfade: $e\n$s');
        }),
      );
    }

    final completer = Completer<void>();
    final stopwatch = Stopwatch()..start();
    final totalMs = fadeDuration.inMilliseconds.clamp(300, 15000);

    _crossfadeTimer?.cancel();
    _crossfadeTimer = Timer.periodic(_fadeTickInterval, (timer) {
      if (_disposed || epoch != _volumeEpoch) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      _outgoingBaseVolume = CrossfadeCurve.outgoingGain(t);
      _primaryBaseVolume = CrossfadeCurve.incomingGain(t);

      unawaited(
        _applyDualVolumes().catchError((Object e, StackTrace s) {
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
      _primaryBaseVolume = 1.0;
      _outgoingBaseVolume = 0.0;
      await _applyPrimaryVolume();
      await _stopOutgoingDeckSafely();
    }
  }

  /// Fallback ultra-seguro si un archivo no pudo cargarse en el deck auxiliar:
  /// atenúa la canción actual, avanza a la siguiente y sube el volumen.
  Future<void> _executeFallbackSingleDeckFade({
    required Duration fadeDuration,
    required int epoch,
  }) async {
    final half = Duration(
      milliseconds: (fadeDuration.inMilliseconds ~/ 2).clamp(200, 3000),
    );
    await _rampPrimaryVolume(from: _primaryBaseVolume, to: 0.0, duration: half, epoch: epoch);
    if (_disposed || epoch != _volumeEpoch) return;
    await _advanceToNext();
    if (_disposed || epoch != _volumeEpoch) return;
    await _rampPrimaryVolume(from: 0.0, to: 1.0, duration: half, epoch: epoch);
  }

  /// Reanuda la reproducción con fundido de entrada suave si está habilitado.
  Future<void> playWithFade() async {
    if (_disposed) return;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    _isFadingOutToPause = false;
    await _stopOutgoingDeckSafely();

    if (!_settings.smoothPlayPauseFade.value) {
      _primaryBaseVolume = 1.0;
      await _applyPrimaryVolume();
      unawaited(
        _primaryPlayer.play().catchError((Object e, StackTrace s) {
          debugPrint('Error en play(): $e\n$s');
        }),
      );
      return;
    }

    // Si ya estaba sonando (p. ej. el usuario canceló una pausa a mitad del
    // fade-out), subimos desde el volumen actual hacia 1.0 sin cortes.
    final startVol = _primaryPlayer.playing ? _primaryBaseVolume : 0.0;
    _primaryBaseVolume = startVol;
    await _applyPrimaryVolume();

    if (!_primaryPlayer.playing) {
      unawaited(
        _primaryPlayer.play().catchError((Object e, StackTrace s) {
          debugPrint('Error iniciando reproducción con fade: $e\n$s');
        }),
      );
    }

    await _rampPrimaryVolume(
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

    if (!_settings.smoothPlayPauseFade.value || !_primaryPlayer.playing) {
      await _stopOutgoingDeckSafely();
      await _primaryPlayer.pause();
      if (!_disposed && epoch == _volumeEpoch) {
        _primaryBaseVolume = 1.0;
        await _applyPrimaryVolume();
      }
      return;
    }

    _isFadingOutToPause = true;
    try {
      final startPrimary = _primaryBaseVolume;
      final startOutgoing = _outgoingBaseVolume;
      final hasOutgoing = _outgoingPlayer?.playing ?? false;

      final stopwatch = Stopwatch()..start();
      final totalMs =
          PlaybackTransitionSettings.playPauseFadeDuration.inMilliseconds;

      while (!_disposed && epoch == _volumeEpoch) {
        final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
        _primaryBaseVolume = CrossfadeCurve.smoothRamp(startPrimary, 0.0, t);
        await _applyPrimaryVolume();
        if (hasOutgoing) {
          _outgoingBaseVolume = CrossfadeCurve.smoothRamp(
            startOutgoing,
            0.0,
            t,
          );
          await _outgoingPlayer?.setVolume(_effectiveOutgoingVolume());
        }
        if (t >= 1.0) break;
        await Future<void>.delayed(_fadeTickInterval);
      }

      if (_disposed || epoch != _volumeEpoch) return;

      await _stopOutgoingDeckSafely();
      await _primaryPlayer.pause();

      // Restaurar ganancia base a 1.0 mientras está en pausa para que cualquier
      // reanudación externa (ej. Bluetooth o sistema) nunca quede muda.
      if (!_disposed && epoch == _volumeEpoch && !_primaryPlayer.playing) {
        _primaryBaseVolume = 1.0;
        await _applyPrimaryVolume();
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
    await _applyDualVolumes();
  }

  /// Pausa la reproducción al concluir la atenuación del Temporizador y
  /// restablece el factor del temporizador a `1.0` de forma segura.
  Future<void> pauseFromSleepTimer() async {
    if (_disposed) return;
    final epoch = ++_volumeEpoch;
    _cancelCrossfadeTimerOnly();
    _isCrossfading = false;
    await _stopOutgoingDeckSafely();
    await _primaryPlayer.pause();
    if (!_disposed && epoch == _volumeEpoch) {
      _sleepTimerFactor = 1.0;
      _primaryBaseVolume = 1.0;
      await _applyPrimaryVolume();
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
      await _applyDualVolumes();
      if (t >= 1.0) break;
      await Future<void>.delayed(_fadeTickInterval);
    }

    if (!_disposed && epoch == _volumeEpoch) {
      _sleepTimerFactor = 1.0;
      await _applyDualVolumes();
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
    _triggeredTrackKey = null;
    _preloadedTrackKey = null;
    _preloadedTrackUri = null;
    await _stopOutgoingDeckSafely();
    if (restoreVolume) {
      _primaryBaseVolume = 1.0;
      await _applyPrimaryVolume();
    }
  }

  Future<void> _rampPrimaryVolume({
    required double from,
    required double to,
    required Duration duration,
    required int epoch,
  }) async {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) {
      _primaryBaseVolume = to;
      await _applyPrimaryVolume();
      return;
    }

    final stopwatch = Stopwatch()..start();
    while (!_disposed && epoch == _volumeEpoch) {
      final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      _primaryBaseVolume = CrossfadeCurve.smoothRamp(from, to, t);
      await _applyPrimaryVolume();
      if (t >= 1.0) break;
      await Future<void>.delayed(_fadeTickInterval);
    }
  }

  double _effectivePrimaryVolume() =>
      (_primaryBaseVolume * _sleepTimerFactor).clamp(0.0, 1.0);

  double _effectiveOutgoingVolume() =>
      (_outgoingBaseVolume * _sleepTimerFactor).clamp(0.0, 1.0);

  Future<void> _applyPrimaryVolume() async {
    if (_disposed) return;
    await _primaryPlayer.setVolume(_effectivePrimaryVolume());
  }

  Future<void> _applyDualVolumes() async {
    if (_disposed) return;
    await _primaryPlayer.setVolume(_effectivePrimaryVolume());
    final deck = _outgoingPlayer;
    if (deck != null && deck.playing) {
      await deck.setVolume(_effectiveOutgoingVolume());
    }
  }

  void _cancelCrossfadeTimerOnly() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
  }

  Future<void> _stopOutgoingDeckSafely() async {
    _outgoingBaseVolume = 0.0;
    final deck = _outgoingPlayer;
    if (deck == null) return;
    try {
      await deck.stop();
      await deck.setVolume(0.0);
    } on Exception catch (e, s) {
      debugPrint('Error deteniendo deck saliente: $e\n$s');
    }
  }

  /// Libera suscripciones, temporizadores y el reproductor auxiliar.
  Future<void> dispose() async {
    _disposed = true;
    _volumeEpoch++;
    _cancelCrossfadeTimerOnly();
    _settings.crossfadeSeconds.removeListener(_onCrossfadeSettingChanged);
    await _positionSub?.cancel();
    _positionSub = null;
    await _outgoingPlayer?.dispose();
    _outgoingPlayer = null;
  }
}
