import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';

/// Servicio singleton para gestionar el temporizador de apagado de música (Sleep Timer).
class SleepTimerService {
  static final SleepTimerService instance = SleepTimerService._internal();
  SleepTimerService._internal();

  Timer? _timer;
  DateTime? _targetEndTime;
  bool _stopAtEndOfSong = false;
  StreamSubscription? _playerSub;

  final ValueNotifier<int?> remainingMinutesNotifier = ValueNotifier<int?>(null);

  bool get isActive => _timer != null || _stopAtEndOfSong;

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
    _targetEndTime = DateTime.now().add(duration);
    remainingMinutesNotifier.value = duration.inMinutes;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (_targetEndTime == null || now.isAfter(_targetEndTime!)) {
        cancelTimer();
        audioHandler.pause();
      } else {
        final diff = _targetEndTime!.difference(now).inMinutes + 1;
        if (remainingMinutesNotifier.value != diff) {
          remainingMinutesNotifier.value = diff;
        }
      }
    });
  }

  void startEndOfSongTimer(AudioHandler audioHandler) {
    cancelTimer();
    _stopAtEndOfSong = true;
    remainingMinutesNotifier.value = -1; // Flag para fin de canción

    String? currentId = audioHandler.mediaItem.value?.id;
    _playerSub = audioHandler.mediaItem.listen((item) {
      if (item != null && currentId != null && item.id != currentId) {
        cancelTimer();
        audioHandler.pause();
      }
    });
  }

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _targetEndTime = null;
    _stopAtEndOfSong = false;
    _playerSub?.cancel();
    _playerSub = null;
    remainingMinutesNotifier.value = null;
  }
}
