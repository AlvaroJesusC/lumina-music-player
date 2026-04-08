import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

/// Manejador principal de audio para Lumina Player.
/// Extiende [BaseAudioHandler] de audio_service para integrarse
/// con la notificación persistente y los controles de media del sistema.
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  // Overrides de metadatos: songId -> {title, artist}
  final Map<String, Map<String, String>> _metadataOverrides = {};

  MediaItem _applyOverride(MediaItem item) {
    final ov = _metadataOverrides[item.id];
    if (ov == null) return item;
    return item.copyWith(
      title: ov['title'] ?? item.title,
      artist: ov['artist'] ?? item.artist,
    );
  }

  MyAudioHandler() {
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      await _player.setLoopMode(LoopMode.all);
      _notifyAudioHandlerAboutPlaybackEvents();
      _listenForSequenceStateChanges();
    } catch (e) {
      debugPrint("Error inicializando player: $e");
    }
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((_) {
      _broadcastState();
    });
    _player.shuffleModeEnabledStream.listen((_) {
      _broadcastState();
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    final queueIndex = _player.currentIndex;

    final processingState =
        (_player.processingState == ProcessingState.ready &&
            _playlist.length == 0)
        ? AudioProcessingState.idle
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex,
        shuffleMode: (_player.shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.sequence;
      if (sequence == null || sequence.isEmpty) return;

      // Actualizar queue aplicando overrides de metadatos
      final items = sequence
          .map((source) => _applyOverride(source.tag as MediaItem))
          .toList();
      queue.add(items);

      // Actualizar mediaItem actual aplicando override si existe
      final currentItem = sequenceState?.currentSource?.tag as MediaItem?;
      if (currentItem != null) {
        mediaItem.add(_applyOverride(currentItem));
      }
    });
  }

  /// Guarda un override de titulo/artista y re-emite los streams
  /// para actualizar el reproductor en tiempo real.
  void updateSongTag(String songId, String newTitle, String newArtist) {
    _metadataOverrides[songId] = {'title': newTitle, 'artist': newArtist};
    _reEmitWithOverrides(songId);
  }

  /// Elimina el override de una cancion (restablecer al original).
  void clearSongTagOverride(String songId) {
    _metadataOverrides.remove(songId);
    _reEmitWithOverrides(songId);
  }

  void _reEmitWithOverrides(String songId) {
    final sequence = _player.sequence;
    if (sequence != null) {
      final updatedItems = sequence
          .map((source) => _applyOverride(source.tag as MediaItem))
          .toList();
      queue.add(updatedItems);
    }
    final currentTag =
        _player.sequenceState?.currentSource?.tag as MediaItem?;
    if (currentTag != null && currentTag.id == songId) {
      mediaItem.add(_applyOverride(currentTag));
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    final audioSources = mediaItems.map(
      (item) => AudioSource.uri(Uri.parse(item.extras!['url']), tag: item),
    );
    await _playlist.clear();
    await _playlist.addAll(audioSources.toList());

    // Si el modo aleatorio está encendido, baraja de nuevo los elementos recién añadidos
    if (_player.shuffleModeEnabled) {
      await _player.shuffle();
    }

    queue.add(mediaItems);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final audioSource = AudioSource.uri(
      Uri.parse(mediaItem.extras!['url']),
      tag: mediaItem,
    );

    // Insertar justo después de la canción actual (Reproducir a continuación)
    int insertIndex = _playlist.length;
    if (_player.currentIndex != null) {
      insertIndex = _player.currentIndex! + 1;
    }

    await _playlist.insert(insertIndex, audioSource);

    // just_audio emitirá el nuevo "sequenceStateStream" y nuestra función
    // _listenForSequenceStateChanges actualizará la queue automáticamente.
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      // Wrap around explicitly when there's no next item
      if (_player.shuffleModeEnabled) {
        await _player.shuffle(); // Reshuffle for a truly infinite random feel
      }
      // Seek to the beginning of the sequence (either original or shuffled)
      int nextIndex = _player.effectiveIndices?.first ?? 0;
      await _player.seek(Duration.zero, index: nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      // Loop back to the end of the playlist
      int lastIndex = _player.effectiveIndices?.last ?? (_playlist.length - 1);
      await _player.seek(Duration.zero, index: lastIndex);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Si el usuario cierra la app deslizando de recientes, y está en pausa,
    // matamos el servicio para que desaparezca la notificación fantasma.
    if (!_player.playing) {
      await stop();
    }
  }
}
