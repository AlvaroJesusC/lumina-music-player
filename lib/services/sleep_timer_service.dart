import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_handler.dart';
import 'playback_transition_settings.dart';

/// Servicio singleton para gestionar el temporizador de apagado de música
/// (Sleep Timer) con bajada progresiva de volumen opcional en los últimos
/// segundos antes de detener la reproducción.
class SleepTimerService {
  static final SleepTimerService instance = SleepTimerService._internal();
  SleepTimerService._internal();

  Timer? _timer;
  Timer? _fadeTimer;
  DateTime? _targetEndTime;
  bool _stopAtEndOfSong = false;
  StreamSubscription<MediaItem?>? _playerSub;
  AudioHandler? _activeHandler;

  final ValueNotifier<int?> remainingMinutesNotifier = ValueNotifier<int?>(null);

  bool get isActive => _timer != null || _fadeTimer != null || _stopAtEndOfSong;

  /// `true` cuando el temporizador está configurado para detenerse al terminar
  /// la canción actual (en ese modo se suprime el crossfade para no cortarla).
  bool get isStopAtEndOfSong => _stopAtEndOfSong;

  String get label {
    if (_stopAtEndOfSong) return 'Fin de canción';
    final remaining = remainingMinutesNotifier.value;
    if (remaining != null && remaining > 0) {
      return '$remaining min';
    }
    return 'Temporizador';
  }

  void startTimer(Duration duration, AudioHandler audioHandler) {
    cancelTimer();
    _stopAtEndOfSong = false;
    _activeHandler = audioHandler;
    _targetEndTime = DateTime.now().add(duration);
    remainingMinutesNotifier.value = duration.inMinutes.clamp(1, 9999);

    final totalMs = duration.inMilliseconds;
    const configuredFadeMs =
        PlaybackTransitionSettings.sleepTimerFadeSeconds * 1000;
    // Si el temporizador es muy corto, la ventana de fade ocupa como máximo la
    // mitad de su duración para no empezar en silencio.
    final effectiveFadeWindowMs = totalMs < configuredFadeMs * 2
        ? (totalMs ~/ 2).clamp(1000, configuredFadeMs)
        : configuredFadeMs;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final endTime = _targetEndTime;
      if (endTime == null) {
        _finishTimerAndPause(audioHandler);
        return;
      }

      final remainingMs = endTime.difference(DateTime.now()).inMilliseconds;
      if (remainingMs <= 0) {
        _finishTimerAndPause(audioHandler);
        return;
      }

      final displayMinutes = (remainingMs / 60000).ceil().clamp(1, 9999);
      if (remainingMinutesNotifier.value != displayMinutes) {
        remainingMinutesNotifier.value = displayMinutes;
      }

      final shouldFadeOut =
          PlaybackTransitionSettings.instance.sleepTimerFadeOut.value;
      if (shouldFadeOut &&
          _fadeTimer == null &&
          remainingMs <= effectiveFadeWindowMs + 1000) {
        _startProgressiveFadeTick(
          audioHandler: audioHandler,
          fadeWindowMs: effectiveFadeWindowMs,
        );
      }
    });
  }

  void _startProgressiveFadeTick({
    required AudioHandler audioHandler,
    required int fadeWindowMs,
  }) {
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final endTime = _targetEndTime;
      if (endTime == null) {
        timer.cancel();
        return;
      }

      final remainingMs = endTime.difference(DateTime.now()).inMilliseconds;
      if (remainingMs <= 0) {
        timer.cancel();
        _finishTimerAndPause(audioHandler);
        return;
      }

      if (!PlaybackTransitionSettings.instance.sleepTimerFadeOut.value) {
        if (audioHandler is MyAudioHandler) {
          unawaited(
            audioHandler.restoreSleepTimerVolume().catchError((
              Object e,
              StackTrace s,
            ) {
              debugPrint('Error restaurando volumen del temporizador: $e\n$s');
            }),
          );
        }
        return;
      }

      final gain = CrossfadeCurve.sleepTimerGain(
        remainingMs: remainingMs,
        fadeWindowMs: fadeWindowMs,
      );
      if (audioHandler is MyAudioHandler) {
        unawaited(
          audioHandler.setSleepTimerVolumeFactor(gain).catchError((
            Object e,
            StackTrace s,
          ) {
            debugPrint('Error aplicando fade del temporizador: $e\n$s');
          }),
        );
      }
    });
  }

  void _finishTimerAndPause(AudioHandler audioHandler) {
    _clearTimersOnly();
    if (audioHandler is MyAudioHandler) {
      unawaited(
        audioHandler.pauseFromSleepTimer().catchError((Object e, StackTrace s) {
          debugPrint('Error pausando al finalizar temporizador: $e\n$s');
        }),
      );
    } else {
      unawaited(
        audioHandler.pause().catchError((Object e, StackTrace s) {
          debugPrint('Error pausando al finalizar temporizador: $e\n$s');
        }),
      );
    }
  }

  void startEndOfSongTimer(AudioHandler audioHandler) {
    cancelTimer();
    _stopAtEndOfSong = true;
    _activeHandler = audioHandler;
    remainingMinutesNotifier.value = -1; // Flag para fin de canción

    final String? currentId = audioHandler.mediaItem.value?.id;
    _playerSub = audioHandler.mediaItem.listen((item) {
      if (item != null && currentId != null && item.id != currentId) {
        _finishTimerAndPause(audioHandler);
      }
    });
  }

  void cancelTimer() {
    final handler = _activeHandler;
    _clearTimersOnly();
    if (handler is MyAudioHandler) {
      unawaited(
        handler.restoreSleepTimerVolume().catchError((Object e, StackTrace s) {
          debugPrint('Error restaurando volumen al cancelar timer: $e\n$s');
        }),
      );
    }
  }

  void _clearTimersOnly() {
    _timer?.cancel();
    _timer = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _targetEndTime = null;
    _stopAtEndOfSong = false;
    unawaited(_playerSub?.cancel());
    _playerSub = null;
    _activeHandler = null;
    remainingMinutesNotifier.value = null;
  }
}
